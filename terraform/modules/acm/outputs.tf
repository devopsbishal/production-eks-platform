output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_id" {
  description = "ID of the ACM certificate"
  value       = aws_acm_certificate.this.id
}

output "domain_name" {
  description = "Primary domain name of the certificate"
  value       = aws_acm_certificate.this.domain_name
}

output "validation_method" {
  description = "Validation method used for certificate"
  value       = aws_acm_certificate.this.validation_method
}
