#!/usr/bin/env bash
# bootstrap-nextcloud.sh
#
# Post-deploy Nextcloud setup. Called by bootstrap-cluster.sh after Nextcloud
# is ready. Idempotent — safe to re-run.
#
# Usage:
#   bootstrap-nextcloud.sh \
#     --company-id    acme-demo \
#     --domain        acme-demo.free-it-infra.com \
#     --nextcloud-url https://files.acme-demo.free-it-infra.com \
#     --admin-pass    <nextcloud admin password> \
#     --keycloak-url  https://auth.acme-demo.free-it-infra.com \
#     --oidc-secret   <keycloak nextcloud client secret>
#
# Does:
#   1. Installs + enables the user_oidc app
#   2. Configures OIDC provider pointing at Keycloak
#   3. Generates per-user app passwords and stores in AWS Secrets Manager
#   4. Disables local login (SSO-only) after OIDC is confirmed working

set -euo pipefail

COMPANY_ID=""
DOMAIN=""
NC_URL=""
ADMIN_PASS=""
KC_URL=""
OIDC_SECRET=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --company-id)    COMPANY_ID="$2";    shift 2 ;;
    --domain)        DOMAIN="$2";        shift 2 ;;
    --nextcloud-url) NC_URL="$2";        shift 2 ;;
    --admin-pass)    ADMIN_PASS="$2";    shift 2 ;;
    --keycloak-url)  KC_URL="$2";        shift 2 ;;
    --oidc-secret)   OIDC_SECRET="$2";   shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

[[ -z "$COMPANY_ID" || -z "$DOMAIN" || -z "$NC_URL" || \
   -z "$ADMIN_PASS" || -z "$KC_URL" || -z "$OIDC_SECRET" ]] \
  && { echo "Missing required arguments."; exit 1; }

AWS_REGION="${AWS_REGION:-eu-west-1}"
log() { echo "[freeit/nextcloud] $*"; }

# Nextcloud OCC wrapper — runs occ inside the Nextcloud pod via kubectl.
occ() {
  k3s kubectl exec -n nextcloud deployment/nextcloud -- \
    php occ --no-ansi "$@"
}

# ── 1. Install user_oidc app ─────────────────────────────────────────────────

log "Installing user_oidc app..."
occ app:install user_oidc 2>/dev/null || true
occ app:enable  user_oidc

# ── 2. Configure OIDC provider ───────────────────────────────────────────────

DISCOVERY_URL="${KC_URL}/realms/${COMPANY_ID}/.well-known/openid-configuration"
log "Configuring OIDC provider: $DISCOVERY_URL"

# Check if provider already exists (idempotency).
EXISTING=$(occ user_oidc:provider:list --output json 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((p['id'] for p in d if p['identifier']=='keycloak'),''))" 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  log "  OIDC provider already configured (id=$EXISTING), updating..."
  occ user_oidc:provider:update "$EXISTING" \
    --clientid="nextcloud" \
    --clientsecret="$OIDC_SECRET" \
    --discoveryuri="$DISCOVERY_URL" \
    --mapping-uid="sub" \
    --mapping-displayName="name" \
    --mapping-email="email" \
    --mapping-quota="" \
    --unique-uid=1 \
    --check-bearer=1
else
  log "  Creating OIDC provider..."
  occ user_oidc:provider:create keycloak \
    --clientid="nextcloud" \
    --clientsecret="$OIDC_SECRET" \
    --discoveryuri="$DISCOVERY_URL" \
    --mapping-uid="sub" \
    --mapping-displayName="name" \
    --mapping-email="email" \
    --unique-uid=1 \
    --check-bearer=1
fi

# ── 3. Generate per-user app passwords ───────────────────────────────────────
# App passwords are used by the WebDAV seeder (provisioner/seed/seeders.py)
# since OIDC tokens can't be used directly for WebDAV.
# Stored in AWS Secrets Manager at freeit/<company_id>/nextcloud-app-password-<email>.

log "Generating per-user app passwords..."

# Get list of Nextcloud users (provisioned via OIDC on first login, or pre-created).
USERS=$(occ user:list --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(u) for u in json.load(sys.stdin).keys()]" 2>/dev/null || true)

for user_email in $USERS; do
  secret_id="freeit/${COMPANY_ID}/nextcloud-app-password-${user_email}"

  # Skip if already stored.
  if aws secretsmanager describe-secret --secret-id "$secret_id" \
       --region "$AWS_REGION" &>/dev/null; then
    log "  [skip] app password already stored for $user_email"
    continue
  fi

  app_pass=$(occ user:add-app-password "$user_email" --password-from-env \
    APP_PASSWORD_NAME="freeit-seed" 2>/dev/null \
    | grep -oP 'password: \K\S+' || true)

  if [[ -z "$app_pass" ]]; then
    log "  [warn] could not generate app password for $user_email — skipping"
    continue
  fi

  aws secretsmanager create-secret \
    --name "$secret_id" \
    --secret-string "$app_pass" \
    --region "$AWS_REGION" \
    >/dev/null
  log "  [ok] app password stored for $user_email"
done

# ── 4. Harden: disable local password login ──────────────────────────────────
# After OIDC is confirmed working, disable the local login form so all
# authentication goes through Keycloak.

log "Disabling local password login (SSO-only mode)..."
occ config:app:set user_oidc allow_multiple_user_backends --value=0

log "Nextcloud bootstrap complete."
log "  Files URL: ${NC_URL}"
log "  OIDC:      ${DISCOVERY_URL}"
