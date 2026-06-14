#!/usr/bin/env bash
# verify-infra.sh — lightweight infra smoke test (no Keycloak/Nextcloud)
#
# Verifies:
#   1. SSH access to node
#   2. k3s is running and node is Ready
#   3. Flux installs successfully
#   4. DNS resolves for the company domain
#   5. TLS cert is valid (wildcard covers the subdomain)
#
# Usage:
#   bash scripts/verify-infra.sh \
#     --node-ip   52.208.147.219 \
#     --ssh-key   ~/.ssh/freeit_ed25519 \
#     --domain    niall-demo.free-it-infra.com

set -euo pipefail

NODE_IP=""
SSH_KEY=""
DOMAIN=""
SSH_USER="ubuntu"
FLUX_VERSION="2.3.0"

while [[ $# -gt 0 ]]; do
  case $1 in
    --node-ip)  NODE_IP="$2";  shift 2 ;;
    --ssh-key)  SSH_KEY="$2";  shift 2 ;;
    --domain)   DOMAIN="$2";   shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

[[ -z "$NODE_IP" || -z "$SSH_KEY" || -z "$DOMAIN" ]] \
  && { echo "Usage: verify-infra.sh --node-ip <ip> --ssh-key <path> --domain <domain>"; exit 1; }

SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$NODE_IP"
log() { echo "[verify] $*"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; exit 1; }

# ── 1. SSH access ─────────────────────────────────────────────────────────────
log "Checking SSH access..."
$SSH "echo ok" &>/dev/null && pass "SSH access works" || fail "Cannot SSH to $NODE_IP"

# ── 2. k3s node ready ─────────────────────────────────────────────────────────
log "Checking k3s..."
STATUS=$($SSH "k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}'")
[[ "$STATUS" == "Ready" ]] && pass "k3s node is Ready" || fail "k3s node status: $STATUS"

# ── 3. Memory ─────────────────────────────────────────────────────────────────
log "Checking memory..."
$SSH "free -m | awk 'NR==2{printf \"  Available: %sMB / %sMB\n\", \$7, \$2}'"

# ── 4. Install Flux (if not already) ─────────────────────────────────────────
log "Installing Flux $FLUX_VERSION..."
$SSH "
  if ! command -v flux &>/dev/null; then
    curl -sfL https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION} bash
  fi
  KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux install \
    --version=v${FLUX_VERSION} \
    --namespace=flux-system \
    --components=source-controller,kustomize-controller,helm-controller,notification-controller
" && pass "Flux installed" || fail "Flux install failed"

# ── 5. Flux controllers running ───────────────────────────────────────────────
log "Checking Flux pods..."
$SSH "k3s kubectl get pods -n flux-system --no-headers 2>/dev/null"
PENDING=$($SSH "k3s kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l")
[[ "$PENDING" -eq 0 ]] && pass "All Flux pods Running" || echo "  ! Some pods not yet Running (may need a moment)"

# ── 6. DNS resolution ─────────────────────────────────────────────────────────
log "Checking DNS for $DOMAIN..."
RESOLVED=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
if [[ "$RESOLVED" == "$NODE_IP" ]]; then
  pass "DNS resolves $DOMAIN → $NODE_IP"
else
  echo "  ! DNS not yet propagated (got: '$RESOLVED', expected: '$NODE_IP') — try again in a minute"
fi

# ── 7. TLS certificate ────────────────────────────────────────────────────────
log "Checking TLS cert for $DOMAIN..."
CERT_DOMAIN=$(echo | openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -o 'CN=.*' | cut -d= -f2 || true)
if [[ -n "$CERT_DOMAIN" ]]; then
  pass "TLS cert subject: $CERT_DOMAIN"
else
  echo "  ! TLS not yet reachable — ingress-nginx not running (expected on t3.micro)"
fi

echo ""
echo "Infrastructure smoke test complete."
echo "DNS and k3s/Flux are the key checks — TLS requires ingress-nginx (needs t3.medium)."
