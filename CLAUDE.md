# Company-in-a-CSV — project constitution

**One line:** A CSV becomes a fully working, isolated company (mail, calendar, files,
onboarding) in minutes, deployable on any cloud.

This file is the single source of truth for project-wide decisions.
If a prompt conflicts with it, this wins. Detailed epic specs live in `files/epics/`.

## Locked decisions (do not relitigate without explicit instruction)

| Decision | Choice | Why |
|---|---|---|
| Tenancy | **Single-tenant** — one isolated deployment per company | Removes multi-tenant control-plane complexity until the business is real |
| Orchestration | **k3s** | Lightweight, isolated-per-company, provider-agnostic, still "Kubernetes" |
| First deliverable | **Recruiter demo** — CSV → live company in minutes | The provisioning engine is the flagship; apps prove it ran |
| Cloud | **AWS-first, provider-agnostic** | Portability is an IaC concern (OpenTofu + k3s-on-any-VM) |
| Region | **EU-based** | GDPR from day one |
| Future | Possible cheap infra for SMBs | Business layer is parked (Phase 5) — do not let it bloat the demo |

## How "provider-agnostic" works

- `infra/modules/CONTRACT.md` — the provider-agnostic interface every `substrate-<cloud>` module honors.
- `infra/README.md` — run order, state strategy, seam map.
- **Hard rule:** cloud SDKs/providers appear **only** inside `infra/modules/substrate-*`.
  Everything portable (cloud-init, k3s, app Helm charts) consumes the `node` contract.

## IaC conventions (E1.1)

- **OpenTofu >= 1.10.** S3 backend with `use_lockfile = true` — no DynamoDB.
- **Client-side state encryption:** AES-GCM + PBKDF2 today (`TF_VAR_state_passphrase`); `aws_kms` is the production target.
- **Per-company state isolation:** `companies/<company_id>/terraform.tfstate`. Never share state between companies.
- **Firewall split:** `ssh_cidrs` (22) and `api_cidrs` (6443) are CIDR-restricted; only `public_ports` (80/443) are world-open.
- **`node_size`** portable enum (`small|medium|large`) — mapped to SKUs inside each substrate. `medium` is the k3s floor.
- **DNS decoupled** from compute — Cloudflare provider (E1.4).

## NEVER

- Reference a cloud SDK/provider outside `substrate-*`.
- Expose k3s API (6443) to `0.0.0.0/0`.
- Commit `state_passphrase`, API tokens, or `*.tfstate`.
- Provision outside EU regions.

## Common commands

Full run order: `infra/README.md`. Quick reference:

```bash
# Bootstrap state bucket (once per account)
tofu -chdir=infra/bootstrap apply -var="state_bucket_name=freeit-tofu-state-prod"

# Per company
export TF_VAR_state_passphrase="..."
tofu -chdir=infra/stacks/company init -reconfigure \
  -backend-config="bucket=freeit-tofu-state-prod" \
  -backend-config="key=companies/<id>/terraform.tfstate" \
  -backend-config="region=eu-west-1"
tofu -chdir=infra/stacks/company apply -var-file="env/<id>.tfvars"

# Before any infra PR
tofu fmt -recursive infra/ && tofu validate
```

## Epic status

| Epic | Title | Status |
|---|---|---|
| E0.1 | Product vision & operating model | DONE |
| E0.2 | Department & app catalog | TODO |
| **E1.1** | **IaC & provider-agnostic provisioning** | **DONE** |
| **E1.2** | **k3s cluster & GitOps** | **DONE** |
| **E1.3** | **Identity & SSO (Keycloak)** | **DONE** |
| **E1.4** | **Networking: wildcard DNS/TLS/ingress** | **DONE** |
| E1.5 | Data layer | TODO |
| E1.6 | Secrets management | TODO |
| E1.7 | Backup & disaster recovery | TODO |
| E1.8 | Observability | TODO |
| E1.9 | Email / SMTP / deliverability | TODO |
| E1.10 | Security hardening & GDPR | TODO |
| **E2.1** | **CSV schema & provisioning engine** | **DONE** |
| E2.2 | Identity provisioning from CSV | TODO |
| **E2.3** | **Seed data generator** | **DONE** |
| E2.4 | Golden-path onboarding template | TODO |
| E3.1 | Nextcloud golden path | TODO |
| E3.2 | Mail & calendar surface | TODO |
| E3.3 | Additional apps | TODO |
| E4.1 | Recruiter onboarding flow | TODO |
| E4.2 | Demo runbook & fallback | TODO |
| E5 | Future business layer | PARKED |
