variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "eks_cluster_endpoint" {
  type        = string
  description = "Endpoint of the EKS cluster"
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

variable "service_account_name" {
  type        = string
  description = "The name of the service account for Karpenter"
  default     = "karpenter"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy Karpenter"
  default     = "karpenter"
}

variable "helm_chart_version" {
  type        = string
  description = "Version of the Karpenter Helm chart"
  default     = "1.8.2"
}


variable "aws_region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed"
}
