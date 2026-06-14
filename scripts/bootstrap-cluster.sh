#!/usr/bin/env bash
# bootstrap-cluster.sh
#
# Called by the provisioning engine (E2.1) after a node is up (E1.1).
# Installs Flux on a fresh k3s node and applies this company's GitOps manifests.
#
# Usage:
#   bootstrap-cluster.sh \
#     --company-id   acme-demo \
#     --node-ip      1.2.3.4 \
#     --ssh-user     ubuntu \
#     --ssh-key      ~/.ssh/freeit_ed25519 \
#     --repo-url     git@github.com:org/freeit.git \
#     --domain       acme-demo.free-it-infra.com \
#     --deploy-key   /path/to/deploy-key \
#     --state-bucket freeit-tofu-state-prod \
#     --aws-region   eu-west-1
#
# The wildcard TLS cert is fetched from S3 (stored there by infra/stacks/platform).
# App secrets are generated once and stored in AWS Secrets Manager — idempotent.
# AWS credentials must be available in the environment (AWS_PROFILE or env vars).
#
# Idempotent: re-running converges without duplicating resources.

set -euo pipefail

FLUX_VERSION="2.3.0"

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
  grep '^#   ' "$0" | sed 's/^#   //'
  exit 1
}

COMPANY_ID=""
NODE_IP=""
SSH_USER="ubuntu"
SSH_KEY=""
REPO_URL=""
DOMAIN=""
DEPLOY_KEY=""
STATE_BUCKET=""
AWS_REGION="eu-west-1"
SECRETS_PREFIX="freeit"
export AWS_REGION   # propagated to bootstrap-realm.sh and any child processes

while [[ $# -gt 0 ]]; do
  case $1 in
    --company-id)   COMPANY_ID="$2";   shift 2 ;;
    --node-ip)      NODE_IP="$2";      shift 2 ;;
    --ssh-user)     SSH_USER="$2";     shift 2 ;;
    --ssh-key)      SSH_KEY="$2";      shift 2 ;;
    --repo-url)     REPO_URL="$2";     shift 2 ;;
    --domain)       DOMAIN="$2";       shift 2 ;;
    --deploy-key)   DEPLOY_KEY="$2";   shift 2 ;;
    --state-bucket) STATE_BUCKET="$2"; shift 2 ;;
    --aws-region)   AWS_REGION="$2";   shift 2 ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
done

[[ -z "$COMPANY_ID" || -z "$NODE_IP" || -z "$SSH_KEY" || -z "$REPO_URL" || \
   -z "$DOMAIN" || -z "$DEPLOY_KEY" || -z "$STATE_BUCKET" ]] \
  && { echo "Missing required arguments."; usage; }

export AWS_REGION   # re-export after arg parsing in case --aws-region was passed
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH="ssh $SSH_OPTS $SSH_USER@$NODE_IP"
SCP="scp $SSH_OPTS"

log() { echo "[freeit] $*"; }

# ── 1. Fetch wildcard TLS cert from S3 ───────────────────────────────────────
# Issued once by infra/stacks/platform (Let's Encrypt DNS-01 via Cloudflare).

log "Fetching wildcard TLS cert from S3..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

WILDCARD_CERT="$TMPDIR/tls.crt"
WILDCARD_KEY_FILE="$TMPDIR/tls.key"

aws s3 cp "s3://${STATE_BUCKET}/platform/wildcard-tls/tls.crt" "$WILDCARD_CERT" \
  --region "$AWS_REGION" --quiet
aws s3 cp "s3://${STATE_BUCKET}/platform/wildcard-tls/tls.key" "$WILDCARD_KEY_FILE" \
  --region "$AWS_REGION" --quiet
log "Wildcard cert fetched."

# ── 2. Generate or retrieve app secrets ──────────────────────────────────────
# Passwords are generated once and stored in AWS Secrets Manager.
# Re-running retrieves existing values — never re-generates.

secret_get_or_create() {
  local name="$1"
  local secret_id="${SECRETS_PREFIX}/${COMPANY_ID}/${name}"
  if aws secretsmanager describe-secret --secret-id "$secret_id" \
       --region "$AWS_REGION" &>/dev/null; then
    aws secretsmanager get-secret-value --secret-id "$secret_id" \
      --region "$AWS_REGION" --query SecretString --output text
  else
    local value
    value=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)
    aws secretsmanager create-secret --name "$secret_id" \
      --secret-string "$value" --region "$AWS_REGION" >/dev/null
    echo "$value"
  fi
}

log "Retrieving/generating app secrets..."
KC_ADMIN_PASS=$(secret_get_or_create "keycloak-admin-password")
KC_PG_PASS=$(secret_get_or_create "keycloak-postgres-password")
KC_PG_USER_PASS=$(secret_get_or_create "keycloak-postgres-user-password")
NC_ADMIN_PASS=$(secret_get_or_create "nextcloud-admin-password")
NC_PG_PASS=$(secret_get_or_create "nextcloud-postgres-password")
NC_PG_USER_PASS=$(secret_get_or_create "nextcloud-postgres-user-password")
NC_PG_REPL_PASS=$(secret_get_or_create "nextcloud-postgres-replication-password")
NC_REDIS_PASS=$(secret_get_or_create "nextcloud-redis-password")

# ── 3. Wait for cloud-init to finish ─────────────────────────────────────────

log "Waiting for node bootstrap to complete on $NODE_IP..."
until $SSH test -f /var/lib/cloud/instance/freeit-bootstrap-complete 2>/dev/null; do
  sleep 10
done
log "Node bootstrap complete."

# ── 4. Wait for k3s to be ready ──────────────────────────────────────────────

log "Waiting for k3s..."
until $SSH "k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'"; do
  sleep 5
done
log "k3s is ready."

# ── 5. Install Flux CLI on the node ──────────────────────────────────────────

log "Installing Flux $FLUX_VERSION on node..."
$SSH "
  if ! command -v flux &>/dev/null; then
    curl -sfL https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION} bash
  else
    echo 'Flux already installed, skipping.'
  fi
"

# ── 6. Pre-populate namespaces and secrets before Flux reconciles ─────────────
# All secrets must exist before HelmReleases that reference them are applied.

log "Creating namespaces..."
for ns in ingress-nginx flux-system keycloak nextcloud cert-manager; do
  $SSH "k3s kubectl create namespace $ns --dry-run=client -o yaml | k3s kubectl apply -f -"
done

log "Uploading wildcard TLS secret..."
CERT_B64=$(base64 < "$WILDCARD_CERT"      | tr -d '\n')
KEY_B64=$(base64  < "$WILDCARD_KEY_FILE"  | tr -d '\n')

$SSH "k3s kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: wildcard-tls
  namespace: ingress-nginx
type: kubernetes.io/tls
data:
  tls.crt: ${CERT_B64}
  tls.key: ${KEY_B64}
EOF"

log "Uploading Keycloak secrets..."
$SSH "k3s kubectl create secret generic keycloak-secrets \
  -n keycloak \
  --from-literal=admin-password='${KC_ADMIN_PASS}' \
  --from-literal=postgres-password='${KC_PG_PASS}' \
  --from-literal=postgres-user-password='${KC_PG_USER_PASS}' \
  --dry-run=client -o yaml | k3s kubectl apply -f -"

log "Uploading Nextcloud secrets..."
$SSH "k3s kubectl create secret generic nextcloud-secrets \
  -n nextcloud \
  --from-literal=admin-username='admin' \
  --from-literal=admin-password='${NC_ADMIN_PASS}' \
  --from-literal=nextcloud-token='$(openssl rand -hex 32)' \
  --from-literal=postgres-password='${NC_PG_PASS}' \
  --from-literal=postgres-user-password='${NC_PG_USER_PASS}' \
  --from-literal=postgres-replication-password='${NC_PG_REPL_PASS}' \
  --from-literal=redis-password='${NC_REDIS_PASS}' \
  --from-literal=smtp-username='' \
  --from-literal=smtp-password='' \
  --dry-run=client -o yaml | k3s kubectl apply -f -"

# ── 7. Upload Flux deploy key (GitHub → cluster read access) ──────────────────

log "Uploading Flux deploy key secret..."
KNOWN_HOSTS=$(ssh-keyscan github.com 2>/dev/null)
$SSH "k3s kubectl create secret generic freeit-deploy-key \
  -n flux-system \
  --from-literal=identity=\"$(cat "$DEPLOY_KEY")\" \
  --from-literal=identity.pub=\"$(cat "${DEPLOY_KEY}.pub")\" \
  --from-literal=known_hosts=\"${KNOWN_HOSTS}\" \
  --dry-run=client -o yaml | k3s kubectl apply -f -"

# ── 8. Bootstrap Flux ─────────────────────────────────────────────────────────

log "Bootstrapping Flux..."
$SSH "KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux install --version=v${FLUX_VERSION} \
  --namespace=flux-system \
  --components-extra=image-reflector-controller,image-automation-controller"

log "Waiting for Flux CRDs to be established..."
$SSH "k3s kubectl wait --for=condition=Established \
  crd/helmreleases.helm.toolkit.fluxcd.io \
  crd/gitrepositories.source.toolkit.fluxcd.io \
  crd/kustomizations.kustomize.toolkit.fluxcd.io \
  crd/helmrepositories.source.toolkit.fluxcd.io \
  --timeout=120s"

# ── 9. Generate and apply per-company cluster manifests ───────────────────────

log "Generating cluster manifests for $COMPANY_ID..."

MANIFEST_DIR="$TMPDIR/manifests"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../gitops/clusters/company-template"

cp -r "$TEMPLATE_DIR" "$MANIFEST_DIR"

# Flux requires ssh:// URL format — convert git@github.com:org/repo to ssh://git@github.com/org/repo
FLUX_REPO_URL=$(python3 -c "
url = '${REPO_URL}'
if url.startswith('git@') and ':' in url:
    host, path = url[4:].split(':', 1)
    url = f'ssh://git@{host}/{path}'
print(url)
")

find "$MANIFEST_DIR" -type f | xargs sed -i.bak \
  -e "s|COMPANY_ID|$COMPANY_ID|g" \
  -e "s|REPO_URL|$FLUX_REPO_URL|g" \
  -e "s|COMPANY_DOMAIN|$DOMAIN|g"
find "$MANIFEST_DIR" -name '*.bak' -delete

$SCP -r "$MANIFEST_DIR" "$SSH_USER@$NODE_IP:/tmp/freeit-cluster-manifests"
$SSH "k3s kubectl apply -k /tmp/freeit-cluster-manifests && rm -rf /tmp/freeit-cluster-manifests"

# ── 10. Wait for Flux reconciliation ──────────────────────────────────────────

log "Waiting for Flux to reconcile (may take 3-5 min)..."
$SSH "KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux reconcile kustomization freeit-${COMPANY_ID} --with-source --timeout=10m"

# ── 11. Bootstrap Keycloak realm ──────────────────────────────────────────────
# Waits for Keycloak to be ready then runs bootstrap-realm.sh.

log "Waiting for Keycloak to be ready..."
$SSH "k3s kubectl rollout status deployment/keycloak -n keycloak --timeout=5m"

SCRIPT_DIR_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR_ABS}/bootstrap-realm.sh" \
  --company-id   "$COMPANY_ID" \
  --domain       "$DOMAIN" \
  --keycloak-url "https://auth.${DOMAIN}" \
  --admin-pass   "$KC_ADMIN_PASS"

# ── 12. Bootstrap Nextcloud ───────────────────────────────────────────────────

log "Waiting for Nextcloud to be ready..."
$SSH "k3s kubectl rollout status deployment/nextcloud -n nextcloud --timeout=10m"

# Fetch the Nextcloud OIDC client secret that bootstrap-realm.sh stored.
NC_OIDC_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "freeit/${COMPANY_ID}/oidc-secret-nextcloud" \
  --region "$AWS_REGION" --query SecretString --output text)

"${SCRIPT_DIR_ABS}/bootstrap-nextcloud.sh" \
  --company-id    "$COMPANY_ID" \
  --domain        "$DOMAIN" \
  --nextcloud-url "https://files.${DOMAIN}" \
  --admin-pass    "$NC_ADMIN_PASS" \
  --keycloak-url  "https://auth.${DOMAIN}" \
  --oidc-secret   "$NC_OIDC_SECRET"

log "────────────────────────────────────────────"
log "Cluster bootstrap complete."
log "  Company  : $COMPANY_ID"
log "  Node     : $SSH_USER@$NODE_IP"
log "  Auth     : https://auth.${DOMAIN}"
log "  Files    : https://files.${DOMAIN}"
log "────────────────────────────────────────────"
