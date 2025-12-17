variable "domain_name" {
  description = "Primary domain name for certificate (e.g., *.eks.rentalhubnepal.com or argocd.eks.rentalhubnepal.com)"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names (SANs) to include in certificate"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation"
  type        = string
}

variable "tags" {
  description = "Tags to apply to ACM certificate"
  type        = map(string)
  default     = {}
}
