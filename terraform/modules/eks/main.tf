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

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group_role" {
  name = "${var.eks_cluster_name}-${var.environment}-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}-node-group-role"
      Environment = var.environment
  })
}

# IAM Role Policy Attachments for EKS Node Group
resource "aws_iam_role_policy_attachment" "eks_node_group_role_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_role_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_role_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

# EKS Node Group
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.eks_cluster_name}-${var.environment}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.node_group_scaling_config.desired_size
    max_size     = var.node_group_scaling_config.max_size
    min_size     = var.node_group_scaling_config.min_size
  }

  update_config {
    max_unavailable = var.node_group_update_config.max_unavailable
  }

  capacity_type  = var.node_group_capacity_type  // e.g., "ON_DEMAND" or "SPOT"
  instance_types = var.node_group_instance_types // List of instance types for the node group

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.environment}-node-group"
      Environment = var.environment
  })

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_role_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_role_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_role_AmazonEC2ContainerRegistryReadOnly,
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
