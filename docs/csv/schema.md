# CSV Schema — Company-in-a-CSV contract

A single CSV file describes one company and all its employees.
The provisioning engine validates this file before touching any infrastructure.

## File structure

Two section types in one file, distinguished by the `record_type` column:

| `record_type` | Purpose |
|---|---|
| `company` | Exactly one row. Company-level settings. |
| `employee` | One row per person. Creates a Keycloak user + assigns apps. |

## Company row

| Column | Required | Example | Notes |
|---|---|---|---|
| `record_type` | yes | `company` | Literal string. |
| `company_id` | yes | `acme-demo` | 3–32 lowercase alphanumeric + hyphens. Immutable once provisioned. |
| `company_name` | yes | `Acme Corp` | Display name used in UI and emails. |
| `root_domain` | yes | `free-it-infra.com` | The platform root domain. |
| `node_size` | no | `medium` | `small\|medium\|large`. Default: `medium`. |
| `aws_region` | no | `eu-west-1` | Must be EU. Default: `eu-west-1`. |
| `substrate` | no | `aws` | Only `aws` today. |
| `recruiter_email` | yes | `alice@recruiter.com` | Real external email — the only address needing real deliverability. Invite is sent here. |

## Employee rows

| Column | Required | Example | Notes |
|---|---|---|---|
| `record_type` | yes | `employee` | Literal string. |
| `company_id` | yes | `acme-demo` | Must match the company row. |
| `email` | yes | `bob@acme-demo.free-it-infra.com` | Login email within the company domain. |
| `first_name` | yes | `Bob` | |
| `last_name` | yes | `Smith` | |
| `role` | yes | `employee` | `employee\|manager\|admin` |
| `department` | no | `Engineering` | Used for seed data grouping (E2.3). |
| `job_title` | no | `Software Engineer` | Used in onboarding pack (E2.4). |
| `apps` | no | `nextcloud,mail` | Comma-separated list of apps to grant. Default: all. |
| `is_onboarding_target` | no | `true` | If `true`, this employee gets a seeded onboarding pack (E2.3). |

## Example CSV

```csv
record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role,department,job_title,apps,is_onboarding_target
company,acme-demo,Acme Corp,free-it-infra.com,medium,alice@recruiter.com,,,,,,,,
employee,acme-demo,,,,bob@acme-demo.free-it-infra.com,Bob,Smith,employee,Engineering,Software Engineer,nextcloud;mail,true
employee,acme-demo,,,,carol@acme-demo.free-it-infra.com,Carol,Jones,manager,Engineering,Engineering Manager,nextcloud;mail,false
employee,acme-demo,,,,dan@acme-demo.free-it-infra.com,Dan,Brown,admin,IT,IT Administrator,nextcloud;mail,false
```

## Validation rules

- Exactly one `company` row per file.
- All `employee` rows must have `company_id` matching the company row.
- `company_id` must match `^[a-z0-9-]{3,32}$`.
- `recruiter_email` must be a valid external email (not on the company domain).
- At least one employee with `role=admin`.
- `aws_region` must match `^eu-`.
- `node_size` must be `small`, `medium`, or `large`.
