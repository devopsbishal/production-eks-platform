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

variable "vpc_id" {
  type        = string
  description = "The VPC ID where the EKS cluster is deployed"
}

variable "aws_region" {
  type        = string
  description = "AWS region where the cluster is deployed"
}

variable "helm_chart_version" {
  type        = string
  description = "Version of the AWS Load Balancer Controller Helm chart"
  default     = "1.11.0"
}

variable "replicas" {
  type        = number
  description = "Number of controller replicas for HA"
  default     = 2
}
