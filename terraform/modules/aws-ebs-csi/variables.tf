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

variable "service_account_name" {
  type        = string
  description = "Name of the service account for the EBS CSI driver"
  default     = "ebs-csi-controller-sa"
}


variable "namespace" {
  type        = string
  description = "Namespace in which the EBS CSI driver is deployed"
  default     = "kube-system"
}


variable "helm_chart_version" {
  type        = string
  description = "Version of the AWS EBS CSI driver Helm chart"
  default     = "2.52.1"
}
