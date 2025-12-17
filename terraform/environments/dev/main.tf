locals {
  eks_cluster_name = "eks-cluster-${var.environment}"
  eks_addon_list = [
    {
      name              = "eks-pod-identity-agent"
      version           = "v1.0.0-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
  ]
}

module "dev-vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
  subnet_config = {
    number_of_public_subnets  = 3
    number_of_private_subnets = 3
  }
  vpc_cidr_block         = "192.168.0.0/16"
  enable_ha_nat_gateways = false
  az_count               = 3
  eks_cluster_name       = local.eks_cluster_name
}

module "dev-eks" {
  source              = "../../modules/eks"
  eks_cluster_name    = "eks-cluster"
  environment         = var.environment
  eks_version         = "1.34"
  authentication_mode = "API"
  subnet_ids          = module.dev-vpc.private_subnet_ids

  # Access entries are defined in terraform.tfvars (gitignored)
  access_entries = var.eks_access_entries
}

module "node_group_general" {
  source           = "../../modules/eks-node-group"
  eks_cluster_name = module.dev-eks.cluster_name
  environment      = var.environment
  subnet_ids       = module.dev-vpc.private_subnet_ids

  node_group_name           = "general"
  node_group_instance_types = ["t3.medium", "t3a.medium", "t3.large", "t3a.large"]
  node_group_capacity_type  = "SPOT"

  node_group_scaling_config = {
    desired_size = 3
    max_size     = 5
    min_size     = 2
  }

  node_group_update_config = {
    max_unavailable            = 1
    max_unavailable_percentage = 0
  }

  depends_on = [module.dev-eks]
}

module "node_group_compute" {
  source           = "../../modules/eks-node-group"
  eks_cluster_name = module.dev-eks.cluster_name
  environment      = var.environment
  subnet_ids       = module.dev-vpc.private_subnet_ids

  node_group_name           = "compute"
  node_group_instance_types = ["c5.xlarge", "c5a.xlarge", "c5.2xlarge", "c5a.2xlarge"]
  node_group_capacity_type  = "SPOT"

  node_group_scaling_config = {
    desired_size = 0
    max_size     = 5
    min_size     = 0
  }

  node_group_update_config = {
    max_unavailable            = 1
    max_unavailable_percentage = 0
  }

  depends_on = [module.dev-eks]
}

# Install EKS AddOns
module "eks_addon" {
  source       = "../../modules/eks-addons"
  addon_list   = local.eks_addon_list
  cluster_name = module.dev-eks.cluster_name
  environment  = var.environment

  depends_on = [module.node_group_general]
}

# EKS Cluster Auth Data
data "aws_eks_cluster_auth" "cluster" {
  name       = module.dev-eks.cluster_name
  depends_on = [module.dev-eks]
}

# Helm Provider Configuration
provider "helm" {
  kubernetes = {
    host                   = module.dev-eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.dev-eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# AWS Load Balancer Controller
module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  eks_cluster_name  = module.dev-eks.cluster_name
  vpc_id            = module.dev-vpc.vpc_id
  aws_region        = var.aws_region
  oidc_provider     = module.dev-eks.oidc_provider
  oidc_provider_arn = module.dev-eks.oidc_provider_arn
  environment       = var.environment

  depends_on = [module.node_group_general, module.node_group_compute]
}

# AWS EBS CSI Driver
# module "aws_ebs_csi" {
#   source             = "../../modules/aws-ebs-csi"
#   cluster_name       = module.dev-eks.cluster_name
#   helm_chart_version = "2.52.1"

#   depends_on = [module.node_group_general, module.node_group_compute]
# }

# Cluster Autoscaler
# module "cluster_autoscaler" {
#   source           = "../../modules/cluster-autoscaler"
#   eks_cluster_name = module.dev-eks.cluster_name
#   aws_region       = var.aws_region
#   environment      = var.environment
#   depends_on       = [module.node_group_compute, module.node_group_general]
# }

# Karpenter
# module "karpenter" {
#   source               = "../../modules/karpenter"
#   eks_cluster_name     = module.dev-eks.cluster_name
#   eks_cluster_endpoint = module.dev-eks.eks_cluster_endpoint
#   aws_region           = var.aws_region
#   environment          = var.environment
#   depends_on           = [module.node_group_general]
# }

# Route53 Hosted Zone for subdomain
module "route53_zone" {
  source = "../../modules/route53-zone"

  domain_name = var.domain_name
  environment = var.environment
}

# External DNS
module "external_dns" {
  source = "../../modules/external-dns"

  eks_cluster_name  = module.dev-eks.cluster_name
  aws_region        = var.aws_region
  oidc_provider     = module.dev-eks.oidc_provider
  oidc_provider_arn = module.dev-eks.oidc_provider_arn
  domain_name       = var.domain_name
  environment       = var.environment

  depends_on = [module.node_group_general, module.node_group_compute, module.route53_zone]
}

# ACM Certificate for EKS subdomain (*.eks.rentalhubnepal.com)
module "acm_certificate" {
  source = "../../modules/acm"

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  route53_zone_id           = module.route53_zone.zone_id

  tags = {
    Name        = "eks-wildcard-cert-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [module.route53_zone]
}

# Argo CD
module "argocd" {
  source = "../../modules/argocd"
  depends_on = [module.aws_load_balancer_controller, module.node_group_general]
}


# Outputs
output "vpc_id" {
  value = module.dev-vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.dev-vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.dev-vpc.private_subnet_ids
}


output "eks_cluster_endpoint" {
  value = module.dev-eks.eks_cluster_endpoint
}

output "eks_cluster_status" {
  value = module.dev-eks.eks_cluster_status
}

output "eks_node_group_status" {
  value = module.node_group_general.eks_node_group_status
}
