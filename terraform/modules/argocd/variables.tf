variable "service_account_name" {
  type        = string
  description = "The name of the service account for Argo CD"
  default     = "argocd"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy Argo CD"
  default     = "argocd"
}

variable "helm_chart_version" {
  type        = string
  description = "Version of the Argo CD Helm chart"
  default     = "9.1.7"
}

variable "argocd_hostname" {
  type        = string
  description = "Hostname for the Argo CD web UI (e.g., argocd.example.com)"
  default     = ""
}
