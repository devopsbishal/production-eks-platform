resource "aws_iam_policy" "external_dns" {
  name   = "${var.eks_cluster_name}-external-dns-policy"
  policy = file("${path.module}/policies/iam-policy.json")

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-external-dns-policy"
      Environment = var.environment
    }
  )
}


# 2. IAM Role with OIDC trust
resource "aws_iam_role" "external_dns" {
  name = "${var.eks_cluster_name}-external-dns-role"

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
          "${var.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:external-dns"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.eks_cluster_name}-external-dns-role"
      Environment = var.environment
    }
  )

}

# 3. Attach policy to role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# 4. Helm release for External DNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.helm_chart_version
  namespace  = var.namespace

  set = [
    # ServiceAccount configuration
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-dns"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_dns.arn
      type  = "string"
    },
    # AWS Route53 provider configuration
    {
      name  = "provider.name"
      value = "aws"
    },
    {
      name  = "env[0].name"
      value = "AWS_DEFAULT_REGION"
    },
    {
      name  = "env[0].value"
      value = var.aws_region
    },
    # Policy: sync (create, update, delete) or upsert-only (create, update)
    {
      name  = "policy"
      value = var.policy
    },
    # Sources to watch for DNS records
    {
      name  = "sources[0]"
      value = "ingress"
    },
    {
      name  = "sources[1]"
      value = "service"
    },
    # Domain filter - only manage records in this domain
    {
      name  = "domainFilters[0]"
      value = var.domain_name
    },
    # TXT record owner ID - prevents conflicts between clusters
    {
      name  = "txtOwnerId"
      value = var.eks_cluster_name
    },
    # Registry type for ownership tracking
    {
      name  = "registry"
      value = "txt"
    },
    # Prefix for TXT records
    {
      name  = "txtPrefix"
      value = "external-dns-"
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.external_dns
  ]
}
