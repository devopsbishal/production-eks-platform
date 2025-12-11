variable "addon_list" {
  type = list(object({
    name              = string
    version           = optional(string)
    resolve_conflicts = optional(string, "OVERWRITE")
  }))
  description = "List of EKS addons to install on the cluster"
}


variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "environment" {
  type        = string
  description = "Environment in which the EKS cluster is deployed"
  default     = "dev"
}

variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}
