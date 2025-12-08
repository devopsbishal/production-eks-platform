
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.eks_cluster_name}-alb-controller"
  policy = file("${path.module}/policies/iam-policy.json")

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-alb-controller-policy"
      Environment = var.environment
    }
  )
}


# 2. IAM Role with OIDC trust
resource "aws_iam_role" "alb_controller" {
  name = "${var.eks_cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-alb-controller-role"
      Environment = var.environment
    }
  )

}

# 3. Attach policy to role
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# 4. Helm release for AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.helm_chart_version
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.alb_controller.arn
      type  = "string"
    },
    {
      name  = "replicaCount"
      value = var.replicas
    },
    {
      name  = "defaultTargetType"
      value = "ip"
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.alb_controller
  ]
}
