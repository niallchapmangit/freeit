#!/usr/bin/env bash
# bootstrap-cluster.sh
#
# Called by the provisioning engine (E2.1) after a node is up (E1.1).
# Installs Flux on a fresh k3s node and applies this company's GitOps manifests.
#
# Usage:
#   bootstrap-cluster.sh \
#     --company-id    acme-demo \
#     --node-ip       1.2.3.4 \
#     --ssh-user      ubuntu \
#     --ssh-key       ~/.ssh/freeit_ed25519 \
#     --repo-url      git@github.com:org/freeit.git \
#     --domain        acme-demo.yourdemo.com \
#     --deploy-key    /path/to/deploy-key          \  # private key for Flux → GitHub
#     --wildcard-cert /path/to/wildcard.crt \
#     --wildcard-key  /path/to/wildcard.key
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
WILDCARD_CERT=""
WILDCARD_KEY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --company-id)    COMPANY_ID="$2";    shift 2 ;;
    --node-ip)       NODE_IP="$2";       shift 2 ;;
    --ssh-user)      SSH_USER="$2";      shift 2 ;;
    --ssh-key)       SSH_KEY="$2";       shift 2 ;;
    --repo-url)      REPO_URL="$2";      shift 2 ;;
    --domain)        DOMAIN="$2";        shift 2 ;;
    --deploy-key)    DEPLOY_KEY="$2";    shift 2 ;;
    --wildcard-cert) WILDCARD_CERT="$2"; shift 2 ;;
    --wildcard-key)  WILDCARD_KEY="$2";  shift 2 ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
done

[[ -z "$COMPANY_ID" || -z "$NODE_IP" || -z "$SSH_KEY" || -z "$REPO_URL" || \
   -z "$DOMAIN" || -z "$DEPLOY_KEY" || -z "$WILDCARD_CERT" || -z "$WILDCARD_KEY" ]] \
  && { echo "Missing required arguments."; usage; }

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH="ssh $SSH_OPTS $SSH_USER@$NODE_IP"
SCP="scp $SSH_OPTS"

log() { echo "[freeit] $*"; }

# ── 1. Wait for cloud-init to finish ─────────────────────────────────────────

log "Waiting for node bootstrap to complete on $NODE_IP..."
until $SSH test -f /var/lib/cloud/instance/freeit-bootstrap-complete 2>/dev/null; do
  sleep 10
done
log "Node bootstrap complete."

# ── 2. Wait for k3s to be ready ──────────────────────────────────────────────

log "Waiting for k3s..."
until $SSH "k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'"; do
  sleep 5
done
log "k3s is ready."

# ── 3. Install Flux CLI on the node ──────────────────────────────────────────

log "Installing Flux $FLUX_VERSION on node..."
$SSH "
  if ! command -v flux &>/dev/null; then
    curl -sfL https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION} bash
  else
    echo 'Flux already installed, skipping.'
  fi
"

# ── 4. Pre-populate the wildcard TLS secret ───────────────────────────────────
# This is what makes new subdomains instantly reachable — no per-company cert issuance.

log "Uploading wildcard TLS secret..."
$SSH "k3s kubectl create namespace ingress-nginx --dry-run=client -o yaml | k3s kubectl apply -f -"
$SSH "k3s kubectl create namespace flux-system  --dry-run=client -o yaml | k3s kubectl apply -f -"

CERT_B64=$(base64 < "$WILDCARD_CERT" | tr -d '\n')
KEY_B64=$(base64  < "$WILDCARD_KEY"  | tr -d '\n')

$SSH "k3s kubectl apply -f - <<'EOF'
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

# ── 5. Upload Flux deploy key (GitHub → cluster read access) ──────────────────

log "Uploading Flux deploy key secret..."
$SSH "k3s kubectl create secret generic freeit-deploy-key \
  --from-file=identity=${DEPLOY_KEY} \
  --from-file=identity.pub=${DEPLOY_KEY}.pub \
  --from-literal=known_hosts=\"\$(ssh-keyscan github.com 2>/dev/null)\" \
  -n flux-system \
  --dry-run=client -o yaml | k3s kubectl apply -f -"

# ── 6. Bootstrap Flux ─────────────────────────────────────────────────────────

log "Bootstrapping Flux..."
$SSH "flux install --version=${FLUX_VERSION} \
  --namespace=flux-system \
  --components-extra=image-reflector-controller,image-automation-controller \
  2>&1 | tail -5"

# ── 7. Generate and apply per-company cluster manifests ───────────────────────
# Renders the company-template, substituting COMPANY_ID / REPO_URL / COMPANY_DOMAIN.

log "Generating cluster manifests for $COMPANY_ID..."

MANIFEST_DIR=$(mktemp -d)
trap 'rm -rf "$MANIFEST_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../gitops/clusters/company-template"

cp -r "$TEMPLATE_DIR"/* "$MANIFEST_DIR/"

# Substitute placeholders
find "$MANIFEST_DIR" -type f | xargs sed -i.bak \
  -e "s|COMPANY_ID|$COMPANY_ID|g" \
  -e "s|REPO_URL|$REPO_URL|g" \
  -e "s|COMPANY_DOMAIN|$DOMAIN|g"
find "$MANIFEST_DIR" -name '*.bak' -delete

# Copy rendered manifests to node and apply
$SCP -r "$MANIFEST_DIR" "$SSH_USER@$NODE_IP:/tmp/freeit-cluster-manifests"
$SSH "k3s kubectl apply -k /tmp/freeit-cluster-manifests && rm -rf /tmp/freeit-cluster-manifests"

# ── 8. Wait for Flux reconciliation ───────────────────────────────────────────

log "Waiting for Flux to reconcile infra layer (may take 3-5 min)..."
$SSH "flux reconcile kustomization freeit-${COMPANY_ID} --with-source --timeout=10m"

log "Cluster bootstrap complete for company: $COMPANY_ID"
log "Node: $SSH_USER@$NODE_IP"
log "Domain: $DOMAIN"
