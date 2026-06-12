# Company-in-a-CSV — Project Context for Claude Code

**One line:** A CSV becomes a fully working, isolated company (mail, calendar, files,
onboarding) in minutes, deployable on any cloud.

This file is shared context for every epic. Each epic lives in its own file under `epics/`.
Read this first, then read the specific `E*.md` epic you are working on.

## Locked decisions (do not relitigate without explicit instruction)

| Decision | Choice | Why it matters |
|---|---|---|
| Tenancy | **One isolated deployment per company** (single-tenant) | Removes the multi-tenant control plane / billing / admin-console work until the business is real |
| Orchestration | **k3s** (lightweight Kubernetes) | Isolated per company on a small node, cheap, provider-agnostic, still "Kubernetes" |
| First deliverable | **Recruiter demo** — CSV → live company in minutes | The *provisioning engine* is the flagship, not Nextcloud; apps are surfaces that prove the engine ran |
| Cloud | **AWS first, provider-agnostic** | Portability is an IaC concern (Terraform/OpenTofu + k3s-on-any-VM), not an orchestrator concern |
| Region context | **EU-based** | GDPR is in scope from day one |
| Future | Possible **cheap infra for SMBs** | Business layer is parked (Phase 5); do not let it bloat the demo |

## The demo critical path (what success looks like)

Recruiter gets an invite in their **real** inbox → logs into the fake company →
finds email, calendar, files, and an onboarding pack already populated.

Architecture choices that make "in minutes" true:
- **Wildcard DNS + pre-issued wildcard TLS cert** — a new company is just a new subdomain
  already covered by DNS + TLS (skips registration, propagation, cert issuance).
- **Provision against warm infrastructure, not a cold cluster** — node already running, so the
  CSV job is just: create instance → deploy charts → create SSO users → seed data.
- **Pre-baked seed data** — beat the empty-shell problem.
- **Only one email needs real deliverability** — the invite to the recruiter's real address;
  everything internal is pre-seeded.
- **Idempotent + re-runnable provisioning** — enables the pre-provisioned fallback + live run.

## Conventions

- **Status values:** `TODO` · `IN PROGRESS` · `DONE` · `PARKED`.
- **Epic file format:** metadata block → Goal → Scope → Depends/Blocks → Deliverable →
  Notes → Definition of Done checklist.
- **Dependency rule:** Phase 1 foundations block the App + provisioning epics. Do not start an
  App epic until the foundations it leans on exist.
- When you finish work on an epic, update its `Status` and tick its Definition-of-Done boxes.

## Suggested first wave (the spine — most unblocking)

`E0.2` (catalog) → `E1.1` (IaC) → `E1.2` (k3s) → `E1.4` (DNS/TLS) → `E1.3` (SSO).
E0.2 can run in parallel with Phase 1 (research doesn't block infra).
