variable "eks_access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    policy_arn        = optional(string, "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy")
    access_scope_type = optional(string, "cluster")
    namespaces        = optional(list(string), [])
  }))
  description = <<-EOT
    Map of access entries for EKS cluster.
    Each entry grants an IAM principal access to the cluster.
    
    Example:
    eks_access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::123456789012:user/admin"
      }
    }
  EOT
  default     = {}
}


variable "aws_region" {
  type        = string
  description = "AWS region where the cluster is deployed"
  default     = "us-west-2"
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route53 hosted zone and External DNS (e.g., aws.example.com)"
}


variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment for the resources"
}
