variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}

variable "eks_cluster_name" {
  type        = string
  description = "The name of the EKS cluster"
}

variable "environment" {
  description = "The environment for the resources"
  type        = string
  default     = "dev"
}

variable "oidc_provider" {
  type        = string
  description = "The OIDC provider URL for the EKS cluster (without https://)"
}

variable "oidc_provider_arn" {
  type        = string
  description = "The ARN of the OIDC provider for the EKS cluster"
}

variable "aws_region" {
  type        = string
  description = "AWS region where the cluster is deployed"
}

variable "helm_chart_version" {
  type        = string
  description = "Version of the External DNS Helm chart"
  default     = "1.18.0"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy External DNS"
  default     = "kube-system"
}

variable "domain_name" {
  type        = string
  description = "Domain name to manage DNS records for (e.g., aws.example.com)"
}

variable "policy" {
  type        = string
  description = "How DNS records are synchronized: sync (create/update/delete), upsert-only (create/update), or create-only (create)"
  default     = "sync"

  validation {
    condition     = contains(["sync", "upsert-only", "create-only"], var.policy)
    error_message = "Policy must be 'sync', 'upsert-only', or 'create-only'."
  }
}
