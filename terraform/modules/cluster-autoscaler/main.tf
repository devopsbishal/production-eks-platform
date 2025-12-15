data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "eks_auto_scaler_role" {
  name               = "${var.eks_cluster_name}-auto-scaler-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-auto-scaler-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "auto_scaler_policy" {
  name   = "${var.eks_cluster_name}-auto-scaler-policy"
  policy = file("${path.module}/policies/iam-policy.json")

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-auto-scaler-policy"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_auto_scaler_role_auto_scaler_policy" {
  policy_arn = aws_iam_policy.auto_scaler_policy.arn
  role       = aws_iam_role.eks_auto_scaler_role.name
}


resource "aws_eks_pod_identity_association" "eks_auto_scaler_pod_identity_association" {
  cluster_name    = var.eks_cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.eks_auto_scaler_role.arn
  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-auto-scaler-pod-identity-association"
      Environment = var.environment
    }
  )
}

resource "helm_release" "aws_eks_cluster_autoscaler" {
  name       = "aws-cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.helm_chart_version
  namespace  = var.namespace

  set = [
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "autoDiscovery.clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "awsRegion"
      value = var.aws_region
    }
  ]
}

