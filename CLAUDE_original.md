# Company-in-a-CSV — project memory

CSV → isolated single-tenant company in minutes, deployable on any cloud.
Flagship use case: the **recruiter demo**. This file is the project constitution;
if a prompt conflicts with it, this wins. Keep it tight.

## Locked decisions (do not relitigate without an explicit ask)
- **Single-tenant.** One company = one isolated unit, all the way down to state.
- **k3s** as the orchestrator (lightweight, runs on any VM).
- **AWS-first but provider-agnostic.** Terraform/OpenTofu + k3s-on-any-VM. AWS is
  the first target; another VPS must drop in behind a thin seam (see below).
- **EU-based / GDPR from day one.** EU regions, encryption, data residency.

## How "provider-agnostic" is implemented (read these, they're authoritative)
- `infra/modules/CONTRACT.md` — the provider-agnostic interface. Every
  `substrate-<cloud>` module honors the same inputs and emits one `node` object.
- `infra/README.md` — run order, state strategy, seam map.
- **Hard rule: cloud SDKs/providers appear ONLY inside `infra/modules/substrate-*`.**
  Anything portable (cloud-init, k3s, app) consumes the `node` contract and never
  imports a cloud SDK. Adding a provider = one new `substrate-<cloud>` module +
  one `count` line in `stacks/company/main.tf` + extend the `coalesce()`.

## IaC conventions established in E1.1 (keep consistent)
- **OpenTofu >= 1.10.** Uses native S3 locking (`use_lockfile = true`) — no
  DynamoDB. Uses native client-side state+plan encryption (pbkdf2 today via
  `TF_VAR_state_passphrase`; `aws_kms` is the production target).
- **Per-company state isolation:** one key `companies/<company_id>/terraform.tfstate`
  via a partial S3 backend injected at init. Same code, isolated state per company.
  Never put multiple companies in one state.
- **Node contract is the E1.1 → E1.2 boundary.** k3s (E1.2) consumes
  `node.public_ip` / `ssh_host` / `ssh_user`. The k3s install hook lives in
  `infra/modules/node-bootstrap/cloud-init.yaml.tftpl`. If E1.2 needs more from
  provisioning, add it to CONTRACT.md, not ad hoc.
- **Firewall is split on purpose:** `ssh_cidrs` (22) and `api_cidrs` (6443) are
  CIDR-restricted; only `public_ports` (default 80/443) are world-open.
- **`node_size`** is a portable enum (`small|medium|large`) mapped to SKUs inside
  each substrate. `medium` is the floor for k3s (small/2 GiB is tight).
- **DNS is decoupled** from the compute provider (Cloudflare provider v5 →
  `cloudflare_dns_record` with `content`, not the v4 `cloudflare_record`/`value`).

## NEVER
- Never reference a cloud provider/SDK outside `substrate-*`.
- Never expose the k3s API (6443) to `0.0.0.0/0`.
- Never commit `state_passphrase`, API tokens, or `*.tfstate`.
- Never provision outside EU regions without an explicit decision.

## Common commands
Full run order is in `infra/README.md`. In short:
- Bootstrap state bucket (once/account): `tofu -chdir=infra/bootstrap apply -var="state_bucket_name=..."`
- Per company: `tofu -chdir=infra/stacks/company init -reconfigure -backend-config=...`
  then `apply -var-file="env/companies/<id>.tfvars"`.
- Before any PR touching infra: `tofu fmt -recursive` and `tofu validate` in the
  changed stack/module.

## Epic status
- **E1.1 (IaC & provisioning): done** — this `infra/` layout.
- **E1.2 (k3s): next** — consumes the node contract; install hook in node-bootstrap.

> Note on placement: if `infra/` is the repo root, this file belongs there. If
> `infra/` is a subfolder of a larger monorepo, put this at the monorepo root and
> the per-stack details stay discoverable via the paths above.
