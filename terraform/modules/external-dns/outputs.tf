output "iam_role_arn" {
  description = "ARN of the IAM role used by External DNS"
  value       = aws_iam_role.external_dns.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by External DNS"
  value       = aws_iam_role.external_dns.name
}

output "namespace" {
  description = "Kubernetes namespace where External DNS is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = "external-dns"
}
