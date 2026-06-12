# Example per-company variable file.
# Copy to env/<company_id>.tfvars and fill in real values.
# NEVER commit real SSH keys, passphrases, or CIDRs to version control.

company_id  = "acme-demo"
substrate   = "aws"
node_size   = "medium"
region      = "eu-west-1"

ssh_public_key = "ssh-ed25519 AAAA... your-key-comment"

# Restrict to your office / VPN CIDR — never 0.0.0.0/0
ssh_cidrs = ["203.0.113.0/24"]
api_cidrs = ["203.0.113.0/24"]

public_ports = [80, 443]

k3s_version = "v1.30.2+k3s1"

tags = {
  Environment = "demo"
  Owner       = "platform-team"
}

# state_passphrase is NOT in this file — set via environment variable:
# export TF_VAR_state_passphrase="your-secret-passphrase"
