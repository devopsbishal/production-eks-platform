variable "domain_name" {
  type        = string
  description = "The domain name for the Route53 hosted zone"
}

variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}


variable "environment" {
  type        = string
  description = "The environment for the Route53 hosted zone (e.g., dev, prod)"
  default     = "dev"
}
