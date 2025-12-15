output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_status" {
  value = aws_eks_cluster.eks_cluster.status
}
output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider" {
  description = "OIDC provider URL (without https://)"
  value       = replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}
