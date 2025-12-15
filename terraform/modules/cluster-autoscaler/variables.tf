variable "eks_cluster_name" {
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

variable "service_account_name" {
  type        = string
  description = "The name of the service account for the Cluster Autoscaler"
  default     = "cluster-autoscaler"
}


variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the Cluster Autoscaler"
  default     = "kube-system"
}


variable "helm_chart_version" {
  type        = string
  description = "Version of the Cluster Autoscaler Helm chart"
  default     = "9.53.0"
}


variable "aws_region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed"
}
