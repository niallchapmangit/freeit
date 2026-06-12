# freeit — Company-in-a-CSV

Turn a CSV file into a fully working, isolated company in minutes.

One command provisions a k3s cluster, deploys Nextcloud (files) and Keycloak (SSO),
creates user accounts, seeds onboarding content, and sends a recruiter invite.

---

## How it works

```
your-company.csv  →  freeit provision  →  live company on free-it-infra.com
```

1. You register a domain on Cloudflare.
2. You fill in `freeit.yaml` with your domain and cloud settings.
3. You create a CSV describing the company and its employees.
4. You run `freeit provision your-company.csv`.

Everything else is automated — infrastructure, DNS, TLS, SSO, files, onboarding content.

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Python | >= 3.11 | Provisioning CLI |
| OpenTofu | >= 1.10 | Infrastructure as Code |
| AWS CLI | any | AWS credentials for OpenTofu and Secrets Manager |
| Helm | >= 3.14 | Resolve Helm chart dependencies |
| A Cloudflare account | — | DNS and wildcard TLS |

AWS credentials must be available in your shell (`AWS_PROFILE` or environment variables).
The AWS account must have access to an EU region (`eu-west-1` by default).

---

## One-time setup (operator)

These steps are done once when you first deploy the platform.
Customers who fork this repo do the same steps for their own domain.

### 1. Register a domain on Cloudflare

Point the domain's nameservers to Cloudflare. Every company gets a
`<company_id>.<root_domain>` subdomain automatically.

### 2. Create a Cloudflare API token

In the Cloudflare dashboard: **My Profile → API Tokens → Create Token**.
Permission required: `Zone:DNS:Edit` for your domain.

### 3. Create the S3 state bucket (once per AWS account)

```bash
tofu -chdir=infra/bootstrap init
tofu -chdir=infra/bootstrap apply \
  -var="state_bucket_name=freeit-tofu-state-prod"
```

### 4. Fill in freeit.yaml

```bash
cp freeit.yaml freeit.yaml   # already in the repo — edit in place
```

Open `freeit.yaml` and set:

| Field | What to put |
|---|---|
| `root_domain` | Your Cloudflare domain (e.g. `free-it-infra.com`) |
| `cloudflare_zone_id` | Right sidebar of your domain in the Cloudflare dashboard |
| `state_bucket` | The S3 bucket name from step 3 |
| `ssh_key` / `ssh_public_key` | Paths to an ED25519 key pair for node access |
| `ssh_cidrs` / `api_cidrs` | Your office or VPN egress IP in CIDR notation |
| `repo_url` | SSH URL of this repo (`git@github.com:org/freeit.git`) |
| `deploy_key` | Path to a read-only SSH deploy key registered on GitHub |
| `ses_from_address` | A verified SES sender address in `eu-west-1` |

### 5. Create a .env file for secrets

```bash
cp .env.example .env
# edit .env — this file is gitignored and must never be committed
```

```
FREEIT_STATE_PASSPHRASE=<strong random passphrase>
FREEIT_CLOUDFLARE_API_TOKEN=<token from step 2>
```

### 6. Issue the wildcard TLS certificate (once)

This creates a `*.free-it-infra.com` certificate via Let's Encrypt DNS-01 and
stores it in S3. All future company subdomains are instantly covered — no
per-company cert issuance needed.

```bash
export CLOUDFLARE_API_TOKEN=$FREEIT_CLOUDFLARE_API_TOKEN

tofu -chdir=infra/stacks/platform init \
  -backend-config="bucket=freeit-tofu-state-prod" \
  -backend-config="key=platform/terraform.tfstate" \
  -backend-config="region=eu-west-1"

tofu -chdir=infra/stacks/platform apply \
  -var="root_domain=free-it-infra.com" \
  -var="cloudflare_zone_id=<your-zone-id>" \
  -var="acme_email=ops@free-it-infra.com" \
  -var="state_bucket=freeit-tofu-state-prod"
```

### 7. Install the provisioning CLI

```bash
pip install -e .
```

---

## Provisioning a company

### Create a CSV file

Copy the example and edit it:

```bash
cp docs/csv/example.csv docs/csv/my-company.csv
```

The CSV has two record types — one `company` row and one `employee` row per person:

```
record_type,company_id,company_name,root_domain,...
company,acme-demo,Acme Corp,free-it-infra.com,medium,recruiter@example.com,...
employee,acme-demo,,,,,alice@acme-demo.free-it-infra.com,Alice,Smith,admin,...
```

See [`docs/csv/schema.md`](docs/csv/schema.md) for all fields.

### Validate before running

```bash
freeit provision docs/csv/my-company.csv --dry-run
```

### Run

```bash
freeit provision docs/csv/my-company.csv
```

The provisioner runs five idempotent steps in order:

| Step | What it does |
|---|---|
| `provision_node` | Creates EC2 instance, DNS records, and EIP via OpenTofu |
| `bootstrap_cluster` | Installs k3s, Flux, Keycloak, and Nextcloud on the node |
| `provision_users` | Creates SSO accounts in Keycloak via Admin REST API |
| `seed_data` | Uploads onboarding files to Nextcloud via WebDAV |
| `send_invite` | Sends recruiter invite email via SES |

Each step is tracked in `~/.freeit/ledger/<company_id>.json`.
Re-running skips completed steps automatically.

### Check status

```bash
freeit status acme-demo
```

### Re-run a single step

```bash
freeit retry docs/csv/my-company.csv --step seed_data
```

---

## Repository layout

```
freeit.yaml                         # Operator config — fill in before first run
.env.example                        # Secret template — copy to .env (gitignored)
docs/
  csv/
    schema.md                       # CSV field reference
    example.csv                     # Example company CSV
infra/
  bootstrap/                        # Run once — creates S3 state bucket
  modules/
    CONTRACT.md                     # Provider-agnostic interface definition
    substrate-aws/                  # AWS-specific: EC2, VPC, SG, EIP
    node-bootstrap/                 # Cloud-agnostic: k3s cloud-init
    dns-cloudflare/                 # Cloudflare DNS records per company
  stacks/
    platform/                       # Run once — wildcard TLS cert
    company/                        # Per-company infrastructure
charts/
  keycloak/                         # Keycloak Helm chart wrapper
  nextcloud/                        # Nextcloud Helm chart wrapper
gitops/
  clusters/
    company-template/               # Flux GitOps manifests (per company)
scripts/
  bootstrap-cluster.sh              # Node setup: Flux, namespaces, secrets
  bootstrap-realm.sh                # Keycloak realm + OIDC clients
  bootstrap-nextcloud.sh            # Nextcloud OIDC config + app passwords
provisioner/
  schema.py                         # CSV validation (Pydantic)
  engine.py                         # Five-step pipeline
  ledger.py                         # Per-company step tracking
  steps/                            # One file per pipeline step
  seed/                             # Onboarding content templates and seeders
```

---

## Security constraints

- Cloud SDK/providers appear **only** inside `infra/modules/substrate-*`
- k3s API port (6443) is **never** exposed to `0.0.0.0/0`
- Secrets live in AWS Secrets Manager — never in manifests or state files
- All infrastructure is provisioned in **EU regions only** (GDPR)
- `*.tfstate`, `.env`, and passphrases are **gitignored**

---

## Epic status

| Epic | Title | Status |
|---|---|---|
| E1.1 | IaC & provider-agnostic provisioning | Done |
| E1.2 | k3s cluster & GitOps | Done |
| E1.3 | Identity & SSO (Keycloak) | Done |
| E1.4 | Networking: wildcard DNS/TLS/ingress | Done |
| E2.1 | CSV schema & provisioning engine | Done |
| E2.3 | Seed data generator | Done |
| E3.1 | Nextcloud golden path | Done |
| E1.5 | Data layer | Planned |
| E1.6 | Secrets management | Planned |
| E2.2 | Identity provisioning from CSV | Planned |
| E3.2 | Mail & calendar surface | Planned |
| E4.1 | Recruiter onboarding flow | Planned |
