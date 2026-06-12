# Epics — Company-in-a-CSV

Shared context lives in [`CLAUDE.md`](./CLAUDE.md). Each epic is a self-contained file below.
Work them in dependency order; the **first wave** (the spine) is starred.

| Epic | Title | Phase | Status | Depends on |
|---|---|---|---|---|
| E0.1 | Product vision & operating model | 0 — Strategy | DONE | — |
| ⭐ E0.2 | Department & application catalog | 0 — Strategy | TODO | — (parallel) |
| ⭐ E1.1 | IaC & provider-agnostic provisioning | 1 — Foundations | TODO | — |
| ⭐ E1.2 | k3s cluster architecture & GitOps | 1 — Foundations | TODO | E1.1 |
| ⭐ E1.3 | Identity & SSO | 1 — Foundations | TODO | E1.2 |
| ⭐ E1.4 | Networking: wildcard DNS, TLS, ingress | 1 — Foundations | TODO | E1.2 |
| E1.5 | Data layer | 1 — Foundations | TODO | E1.2 |
| E1.6 | Secrets management | 1 — Foundations | TODO | E1.2 |
| E1.7 | Backup & disaster recovery | 1 — Foundations | TODO | E1.5 |
| E1.8 | Observability | 1 — Foundations | TODO | E1.2 |
| E1.9 | Email/SMTP & deliverability | 1 — Foundations | TODO | E1.4 |
| E1.10 | Security hardening & GDPR | 1 — Foundations | TODO | E1.2 |
| E2.1 | CSV schema & provisioning engine ⟵ centerpiece | 2 — Provisioning | TODO | E1.1–E1.6 |
| E2.2 | Identity provisioning from CSV | 2 — Provisioning | TODO | E1.3, E2.1 |
| E2.3 | Seed-data generator | 2 — Provisioning | TODO | E2.1, E3.1, E3.2 |
| E2.4 | Golden-path app onboarding template | 2 — Provisioning | TODO | E1.2/3/5/7/8 |
| E3.1 | Nextcloud (+ establishes golden path) | 3 — Applications | TODO | E1.2/3/4/5 |
| E3.2 | Mail/calendar surface | 3 — Applications | TODO | E1.3, E1.9, E2.4 |
| E3.3 | Additional apps (App N) | 3 — Applications | TODO | E2.4, E0.2 |
| E4.1 | Recruiter onboarding flow | 4 — Demo | TODO | E2.x, E3.x |
| E4.2 | Demo runbook & fallback | 4 — Demo | TODO | E2.1, E4.1 |
| E5 | Future business layer | 5 — Business | PARKED | — |

**Dependency rule:** Phase 1 foundations block the App + provisioning epics.
