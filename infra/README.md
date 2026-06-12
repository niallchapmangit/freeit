# infra — OpenTofu layout

> OpenTofu >= 1.10 required. AWS CLI configured with EU-region credentials.

## Directory layout

```
infra/
├── bootstrap/                  # Run once per AWS account — creates the state bucket
│   └── main.tf
├── modules/
│   ├── CONTRACT.md             # The provider-agnostic interface (read this first)
│   ├── substrate-aws/          # AWS-specific: EC2 + VPC + SG + EIP
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── node-bootstrap/         # Cloud-agnostic: cloud-init template + k3s install
│       ├── main.tf
│       ├── variables.tf
│       └── cloud-init.yaml.tftpl
└── stacks/
    └── company/                # Per-company entrypoint (isolated state per company)
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── env/
            └── example.tfvars  # Copy and fill in per company
```

## Run order

### Step 1 — Bootstrap (once per AWS account)

Creates the encrypted, versioned, EU-region S3 state bucket.

```bash
tofu -chdir=infra/bootstrap init
tofu -chdir=infra/bootstrap apply \
  -var="state_bucket_name=freeit-tofu-state-prod"
```

Note the `state_bucket_name` output — you need it for every company init.

---

### Step 2 — Per-company provisioning

**Prepare variables:**

```bash
cp infra/stacks/company/env/example.tfvars infra/stacks/company/env/acme-demo.tfvars
# Edit acme-demo.tfvars with real values
export TF_VAR_state_passphrase="your-secret-passphrase"   # never commit this
```

**Init with per-company backend:**

```bash
tofu -chdir=infra/stacks/company init -reconfigure \
  -backend-config="bucket=freeit-tofu-state-prod" \
  -backend-config="key=companies/acme-demo/terraform.tfstate" \
  -backend-config="region=eu-west-1"
```

**Plan and apply:**

```bash
tofu -chdir=infra/stacks/company plan \
  -var-file="env/acme-demo.tfvars"

tofu -chdir=infra/stacks/company apply \
  -var-file="env/acme-demo.tfvars"
```

---

### Before any PR touching infra

```bash
tofu fmt -recursive infra/
tofu validate   # run inside the changed stack/module directory
```

---

## State strategy

- **One state file per company** at `companies/<company_id>/terraform.tfstate` in S3.
- **S3 native locking** (`use_lockfile = true`) — no DynamoDB needed (OpenTofu >= 1.10).
- **Client-side encryption** (AES-GCM, PBKDF2 key from `TF_VAR_state_passphrase`).
  Production target: swap PBKDF2 for `aws_kms` key provider.
- **Never share state between companies.** `-reconfigure` at init enforces isolation.

---

## Provider seam map

The seam lives between `modules/substrate-*` and everything above it.

| Layer | What lives here | Can reference cloud? |
|---|---|---|
| `substrate-aws/` | EC2, VPC, SG, EIP | Yes — AWS only |
| `substrate-<other>/` | Hetzner/DigitalOcean/etc. resources | Yes — that provider only |
| `node-bootstrap/` | cloud-init, k3s install | No |
| `stacks/company/` | wires modules together, state config | No (calls substrate via module) |
| App Helm charts | k3s workloads | No |

**Adding a new provider:**

1. Create `infra/modules/substrate-<cloud>/` implementing the contract in `CONTRACT.md`.
2. Add a `count`-gated module call in `stacks/company/main.tf`.
3. Extend the `coalesce()` in `locals.node`.
4. Add the new provider to the `substrate` variable validation list.

**Cost to add a second provider:** ~100 lines of HCL + one `coalesce()` line. No other files change.

---

## NEVER

- Reference a cloud SDK/provider outside `substrate-*`.
- Expose k3s API (6443) to `0.0.0.0/0` — validated at the module level.
- Commit `state_passphrase`, API tokens, or `*.tfstate`.
- Provision outside EU regions — validated at the module level.
