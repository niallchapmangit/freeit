# Platform stack — run once to issue the wildcard TLS cert.
# Copy to env/prod.tfvars and fill in real values.
# NEVER commit API tokens or passphrases.

root_domain       = "free-it-infra.com"
acme_email        = "ops@free-it-infra.com"
state_bucket_name = "freeit-tofu-state-prod"
aws_region        = "eu-west-1"

# Set these via environment variables — never in this file:
# export TF_VAR_cloudflare_api_token="..."
# export TF_VAR_cloudflare_zone_id="..."
# export TF_VAR_state_passphrase="..."
