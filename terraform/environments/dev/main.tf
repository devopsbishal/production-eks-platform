module "dev-vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
  subnet_config = {
    number_of_public_subnets  = 3
    number_of_private_subnets = 3
  }
  vpc_cidr_block         = "192.168.0.0/16"
  enable_ha_nat_gateways = false
}

module "dev-eks" {
  source              = "../../modules/eks"
  eks_cluster_name    = "eks-cluster"
  environment         = "dev"
  eks_version         = "1.34"
  authentication_mode = "API"
  subnet_ids          = module.dev-vpc.private_subnet_ids

  # Access entries are defined in terraform.tfvars (gitignored)
  access_entries = var.eks_access_entries
}

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
