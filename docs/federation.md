# Federation pattern — how apps connect to Keycloak

Every app in a company cluster federates to the company's Keycloak realm via OIDC.
This document is the reference for app authors and the provisioning engine (E2.2).

## Identity topology

```
CSV row (employee)
    │
    ▼
Keycloak realm: <company_id>
    │   (OIDC / Authorization Code + PKCE)
    ├── Nextcloud        → https://files.<company>.free-it-infra.com
    ├── Mail (Roundcube) → https://mail.<company>.free-it-infra.com
    └── Portal           → https://<company>.free-it-infra.com
```

One realm per company. One OIDC client per app. Client secrets stored in
AWS Secrets Manager at `freeit/<company_id>/oidc-secret-<app>`.

## OIDC discovery endpoint

```
https://auth.<company_id>.free-it-infra.com/realms/<company_id>/.well-known/openid-configuration
```

All apps use this URL — they need no other Keycloak configuration.

## How an app configures OIDC (the pattern)

Each app's Helm `values.yaml` accepts:

```yaml
oidc:
  issuerUrl: "https://auth.${company_domain}/realms/${company_id}"
  clientId: "<app-name>"          # e.g. nextcloud, mail
  clientSecret: ""                # injected from a Kubernetes Secret at deploy time
  redirectUri: "https://<app>.<company_domain>/oauth/callback"
```

The provisioning engine (E2.2) fetches `oidc.clientSecret` from AWS Secrets Manager
(`freeit/<company_id>/oidc-secret-<app>`) and writes it into a Kubernetes Secret
in the app's namespace before Helm installs the chart.

## Authorization Code + PKCE flow

```
Browser → App → Keycloak /auth  (redirect)
             ← Keycloak /token  (code exchange)
             → App session established
```

- `standardFlowEnabled: true` — Authorization Code flow
- `directAccessGrantsEnabled: false` — no password grant (security)
- `pkce.code.challenge.method: S256` — PKCE enforced on confidential clients
- `publicClient: false` for server-side apps (Nextcloud, Roundcube)
- `publicClient: true` for the portal (SPA, no server secret)

## Adding a new app (checklist)

1. Add a new `upsert_client` call in `scripts/bootstrap-realm.sh`.
2. Store the client secret in Secrets Manager: `freeit/<company_id>/oidc-secret-<app>`.
3. In the app's Helm chart `values.yaml`, add the `oidc` block above.
4. In the app's deployment, mount the secret and pass the env vars the app expects.
5. Point the app's OIDC config at the discovery URL — no hardcoded endpoints.

## E2.2 — User CRUD API path

The provisioning engine creates users via the **Keycloak Admin REST API**:

| Operation | Endpoint | Notes |
|---|---|---|
| Create user | `POST /admin/realms/<realm>/users` | Body: `{username, email, firstName, lastName, enabled: true}` |
| Set temp password | `PUT /admin/realms/<realm>/users/<id>/reset-password` | `{type:"password", value:"...", temporary:true}` |
| Assign role | `POST /admin/realms/<realm>/users/<id>/role-mappings/realm` | Body: array of role objects |
| Get user by email | `GET /admin/realms/<realm>/users?email=<email>` | For idempotency check |

Authentication: client credentials grant from the `admin-cli` client in the master realm
using the `admin` user credentials (stored at `freeit/<company_id>/keycloak-admin-password`).

Token endpoint: `https://auth.<company>.free-it-infra.com/realms/master/protocol/openid-connect/token`

## Idempotency

`bootstrap-realm.sh` uses `GET → PUT (if exists) / POST (if not)` for all resources.
Re-running is safe and converges — no duplicates.
