
variable "node_group_name" {
  type        = string
  description = "The name of the EKS node group"
}

variable "environment" {
  type        = string
  description = "The environment for the EKS cluster"
  default     = "dev"
}

variable "eks_cluster_name" {
  type        = string
  description = "The name of the EKS cluster"
  default     = "test-eks-cluster"
}

variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the EKS cluster"
  default     = []
}

variable "node_group_scaling_config" {
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
  description = "Scaling configuration for the EKS node group"
  default = {
    desired_size = 4
    max_size     = 6
    min_size     = 2
  }
}

variable "node_group_update_config" {
  type = object({
    max_unavailable            = number
    max_unavailable_percentage = number
  })
  description = "Update configuration for the EKS node group"
  default = {
    max_unavailable            = 1
    max_unavailable_percentage = 0
  }
}

variable "node_group_instance_types" {
  type        = list(string)
  description = "The instance type for the EKS node group"
}

variable "node_group_capacity_type" {
  type        = string
  description = "The capacity type for the EKS node group (ON_DEMAND or SPOT)"
  default     = "SPOT"
}

