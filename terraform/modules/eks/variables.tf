variable "eks_version" {
  type        = string
  description = "The Kubernetes version for the EKS cluster"
  default     = "1.34"
}

variable "environment" {
  type        = string
  description = "The environment for the EKS cluster"
  default     = "dev"
}

variable "authentication_mode" {
  type        = string
  description = "The authentication mode for the EKS cluster"
  default     = "API"
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

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    policy_arn        = optional(string, "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy")
    access_scope_type = optional(string, "cluster")
    namespaces        = optional(list(string), [])
  }))
  description = <<-EOT
    Map of access entries to create for the EKS cluster.
    Each entry grants an IAM principal access to the cluster.
    
    - principal_arn: ARN of the IAM user or role
    - type: Type of access entry (STANDARD, FARGATE_LINUX, EC2_LINUX, EC2_WINDOWS)
    - policy_arn: EKS access policy ARN to associate
    - access_scope_type: Scope of access (cluster or namespace)
    - namespaces: List of namespaces (only used when access_scope_type is "namespace")
    
    Available policies:
    - arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy (full admin)
    - arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy (admin without IAM)
    - arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy (edit resources)
    - arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy (read-only)
  EOT
  default     = {}
}
