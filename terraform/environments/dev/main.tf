module "dev-vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
}
