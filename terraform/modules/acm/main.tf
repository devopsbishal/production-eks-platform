# Request ACM certificate
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Auto-create Route53 validation record (single record - wildcard and base domain share same validation)
resource "aws_route53_record" "validation" {
  allow_overwrite = true
  zone_id         = var.route53_zone_id
  name            = tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_value]
  ttl             = 60
}

# Wait for validation to complete
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [aws_route53_record.validation.fqdn]
}
