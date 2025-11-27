variable "resource_tag" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}


variable "vpc_subnets" {
  description = "List of subnets"
  type = list(object({
    cidr_block              = string
    availability_zone       = string
    map_public_ip_on_launch = bool
  }))

  default = [
    {
      cidr_block              = "10.0.0.0/19"
      availability_zone       = "us-west-2a"
      map_public_ip_on_launch = true
    },
    {
      cidr_block              = "10.0.32.0/19"
      availability_zone       = "us-west-2b"
      map_public_ip_on_launch = true
    },
    {
      cidr_block              = "10.0.64.0/19"
      availability_zone       = "us-west-2c"
      map_public_ip_on_launch = true
    },
    {
      cidr_block              = "10.0.96.0/19"
      availability_zone       = "us-west-2a"
      map_public_ip_on_launch = false
    },
    {
      cidr_block              = "10.0.128.0/19"
      availability_zone       = "us-west-2b"
      map_public_ip_on_launch = false
    },
    {
      cidr_block              = "10.0.160.0/19"
      availability_zone       = "us-west-2c"
      map_public_ip_on_launch = false
    }
  ]
}


variable "environment" {
  description = "The environment for the resources"
  type        = string
  default     = "development"
}
