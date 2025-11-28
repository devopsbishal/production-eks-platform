module "dev-vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
  subnet_config = {
    number_of_public_subnets  = 4
    number_of_private_subnets = 3
  }
  vpc_cidr_block = "192.168.0.0/16"
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
