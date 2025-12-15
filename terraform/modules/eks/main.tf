# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.eks_cluster_name}-${var.environment}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}-role"
      Environment = var.environment
  })
}

# IAM Role Policy Attachment for EKS Cluster
resource "aws_iam_role_policy_attachment" "eks_cluster_role_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name = "${var.eks_cluster_name}-${var.environment}"

  access_config {
    authentication_mode = var.authentication_mode
  }

  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}"
      Environment = var.environment
  })

  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_role_AmazonEKSClusterPolicy,
  ]
}

# EKS Access Entries - Grant IAM principals access to the cluster
resource "aws_eks_access_entry" "access_entries" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value.principal_arn
  type          = each.value.type

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}-access-entry-${each.key}"
      Environment = var.environment
  })
}

# EKS Access Policy Association - Associate policies with access entries
resource "aws_eks_access_policy_association" "access_policy_associations" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.access_scope_type == "namespace" ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.access_entries]
}

# OIDC Provider for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}-oidc-provider"
      Environment = var.environment
    }
  )
}

# Tag the cluster security group for Karpenter discovery
resource "aws_ec2_tag" "cluster_security_group_tag" {
  resource_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "${var.eks_cluster_name}-${var.environment}"
}
