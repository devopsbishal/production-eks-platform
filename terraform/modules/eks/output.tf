output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_status" {
  value = aws_eks_cluster.eks_cluster.status
}

output "eks_node_group_status" {
  value = aws_eks_node_group.eks_node_group.status
}
