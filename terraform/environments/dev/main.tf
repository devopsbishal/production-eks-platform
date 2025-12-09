locals {
  eks_cluster_name = "eks-cluster-${var.environment}"
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

  depends_on = [module.dev-eks]
}

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

  depends_on = [module.dev-eks, module.route53_zone]
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
  value = module.dev-eks.eks_node_group_status
}
