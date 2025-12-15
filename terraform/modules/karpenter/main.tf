# ==============================================================================
# Karpenter AWS Resources (IAM, SQS, EventBridge)
# ==============================================================================

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.0.1"

  cluster_name = var.eks_cluster_name

  # Pod Identity configuration
  create_pod_identity_association = true                     # Use EKS Pod Identity
  namespace                       = var.namespace            # Namespace for Pod Identity association
  service_account                 = var.service_account_name # Service account for Pod Identity association

  # Node IAM role configuration
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "KarpenterNodeRole-${var.eks_cluster_name}"

  # Additional policies for node role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-karpenter"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# Helm Release for Karpenter
# ==============================================================================

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.helm_chart_version
  namespace  = var.namespace

  create_namespace = true

  set = [
    {
      name  = "settings.clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "settings.clusterEndpoint"
      value = var.eks_cluster_endpoint
    },
    {
      name  = "settings.interruptionQueue"
      value = module.karpenter.queue_name
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "1"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "1Gi"
    },
    {
      name  = "controller.resources.limits.cpu"
      value = "1"
    },
    {
      name  = "controller.resources.limits.memory"
      value = "1Gi"
    }
  ]

  depends_on = [module.karpenter]
}
