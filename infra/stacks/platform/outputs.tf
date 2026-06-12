output "wildcard_cert_s3_key" {
  description = "S3 key for the wildcard certificate PEM (full chain)."
  value       = aws_s3_object.wildcard_cert.key
}

output "wildcard_key_s3_key" {
  description = "S3 key for the wildcard private key PEM."
  value       = aws_s3_object.wildcard_key.key
}

output "cert_expiry" {
  description = "Wildcard cert expiry date — renew before this."
  value       = acme_certificate.wildcard.certificate_not_after
}
