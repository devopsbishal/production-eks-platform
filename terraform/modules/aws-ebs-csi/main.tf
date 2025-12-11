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

resource "aws_iam_role" "eks_ebs_role" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.cluster_name}-ebs-csi-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_ebs_role_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks_ebs_role.name
}


resource "aws_eks_pod_identity_association" "eks_ebs_csi_pod_identity_association" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.eks_ebs_role.arn

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.cluster_name}-ebs-csi-pod-identity-association"
      Environment = var.environment
    }
  )
}

resource "helm_release" "aws_ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  version    = var.helm_chart_version
  namespace  = var.namespace

  set = [
    {
      name  = "controller.serviceAccount.create"
      value = "true"
    },
    {
      name  = "controller.serviceAccount.name"
      value = var.service_account_name
    }
  ]
}

