
locals {
  capacity_type = contains(["ON_DEMAND", "SPOT"], var.node_group_capacity_type) ? var.node_group_capacity_type : "SPOT"
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group_role" {
  name = "${var.eks_cluster_name}-${var.node_group_name}-node-group-role"

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
      Name        = "${var.eks_cluster_name}-${var.node_group_name}-node-group-role"
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
  cluster_name    = var.eks_cluster_name
  node_group_name = "${var.eks_cluster_name}-${var.node_group_name}-node-group"
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

  capacity_type  = local.capacity_type           // e.g., "ON_DEMAND" or "SPOT"
  instance_types = var.node_group_instance_types // List of instance types for the node group

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-${var.node_group_name}-node-group"
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
