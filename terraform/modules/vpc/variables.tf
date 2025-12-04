variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC. Subnets will be automatically calculated using /19 masks."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "A list of availability zones to use for the subnets"
  type        = list(string)
  default     = null
}

variable "az_count" {
  description = "Number of availability zones to use for subnet distribution"
  type        = number
  default     = 3
}

variable "subnet_config" {
  description = "A map containing subnet configuration data"
  type = object({
    number_of_public_subnets  = number
    number_of_private_subnets = number
  })
  default = {
    number_of_public_subnets  = 3
    number_of_private_subnets = 3
  }
}


variable "environment" {
  description = "The environment for the resources"
  type        = string
  default     = "development"
}

variable "enable_ha_nat_gateways" {
  description = "Whether to enable high availability NAT Gateways in each public subnet"
  type        = bool
  default     = true
}

variable "internet_cidr_block" {
  description = "CIDR block for internet-bound traffic (default route)"
  type        = string
  default     = "0.0.0.0/0"
}
