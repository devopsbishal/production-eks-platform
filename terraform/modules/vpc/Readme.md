# VPC Module

A production-ready AWS VPC module with dynamic subnet generation, NAT Gateway high availability options, and EKS-ready tagging.

## Features

- 🔄 **Dynamic Subnet Generation** - Automatically calculates CIDR blocks using `cidrsubnet()`
- 🏗️ **Multi-AZ Architecture** - Distributes subnets across availability zones
- 🌐 **NAT Gateway HA** - Toggle between single NAT (cost-saving) or multi-AZ NAT (high availability)
- 🏷️ **Kubernetes Ready** - Pre-configured subnet tags for EKS ELB discovery
- 📦 **Flexible Configuration** - Customize subnet counts, CIDR blocks, and AZs

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPC (var.vpc_cidr_block)                │
└─────────────────────────────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│     AZ-A      │         │     AZ-B      │         │     AZ-C      │
├───────────────┤         ├───────────────┤         ├───────────────┤
│ Public Subnet │         │ Public Subnet │         │ Public Subnet │
│   + NAT GW*   │         │   + NAT GW*   │         │   + NAT GW*   │
├───────────────┤         ├───────────────┤         ├───────────────┤
│Private Subnet │         │Private Subnet │         │Private Subnet │
│ (EKS Workers) │         │ (EKS Workers) │         │ (EKS Workers) │
└───────────────┘         └───────────────┘         └───────────────┘

* NAT Gateway per AZ when enable_ha_nat_gateways = true
  Single NAT in first AZ when enable_ha_nat_gateways = false
```

## Usage

### Basic Usage (with defaults)

```hcl
module "vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
}
```

### Custom Configuration

```hcl
module "vpc" {
  source      = "../../modules/vpc"
  environment = "prod"
  
  vpc_cidr_block = "172.16.0.0/16"
  
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  subnet_config = {
    number_of_public_subnets  = 3
    number_of_private_subnets = 3
  }
  
  enable_ha_nat_gateways = true  # HA mode: NAT per AZ
  
  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "my-project"
    Team      = "platform"
  }
}
```

### Cost-Optimized (Dev/Staging)

```hcl
module "vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
  
  subnet_config = {
    number_of_public_subnets  = 2
    number_of_private_subnets = 2
  }
  
  enable_ha_nat_gateways = false  # Single NAT: ~$32/month vs ~$96/month
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `environment` | Environment name (dev/staging/prod) | `string` | `"development"` | no |
| `vpc_cidr_block` | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| `availability_zones` | List of AZs to use | `list(string)` | `["us-west-2a", "us-west-2b", "us-west-2c"]` | no |
| `subnet_config` | Subnet configuration object | `object` | See below | no |
| `enable_ha_nat_gateways` | Enable NAT Gateway per AZ for HA | `bool` | `true` | no |
| `internet_cidr_block` | CIDR for internet-bound traffic | `string` | `"0.0.0.0/0"` | no |
| `resource_tag` | Common tags for all resources | `map(string)` | See below | no |

### subnet_config Default

```hcl
{
  number_of_public_subnets  = 3
  number_of_private_subnets = 3
}
```

### resource_tag Default

```hcl
{
  ManagedBy = "Terraform"
  Project   = "production-eks-platform"
}
```

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | The ID of the VPC |
| `vpc_cidr_block` | The CIDR block of the VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `internet_gateway_id` | The ID of the Internet Gateway |
| `public_route_table_id` | The ID of the public route table |
| `private_route_table_ids` | Map of private route table IDs by subnet key |

## How Dynamic Subnet Generation Works

The module automatically calculates subnet CIDRs based on your configuration:

```hcl
locals {
  total_subnets = var.subnet_config.number_of_public_subnets + var.subnet_config.number_of_private_subnets
  new_bits      = ceil(log(local.total_subnets, 2))
  
  vpc_subnets = [
    for idx in range(local.total_subnets) : {
      cidr_block              = cidrsubnet(var.vpc_cidr_block, local.new_bits, idx)
      availability_zone       = var.availability_zones[idx % length(var.availability_zones)]
      map_public_ip_on_launch = idx < var.subnet_config.number_of_public_subnets
    }
  ]
}
```

### Example Calculation

| Input | Value |
|-------|-------|
| VPC CIDR | `10.0.0.0/16` |
| Public subnets | 3 |
| Private subnets | 3 |

| Calculation | Result |
|-------------|--------|
| Total subnets | 6 |
| new_bits = ceil(log(6, 2)) | 3 |
| Subnet mask = /16 + 3 | /19 |
| IPs per subnet | 8,192 |

| Generated Subnets | CIDR | Type | AZ |
|-------------------|------|------|-----|
| Subnet 0 | `10.0.0.0/19` | Public | us-west-2a |
| Subnet 1 | `10.0.32.0/19` | Public | us-west-2b |
| Subnet 2 | `10.0.64.0/19` | Public | us-west-2c |
| Subnet 3 | `10.0.96.0/19` | Private | us-west-2a |
| Subnet 4 | `10.0.128.0/19` | Private | us-west-2b |
| Subnet 5 | `10.0.160.0/19` | Private | us-west-2c |

## NAT Gateway Modes

### High Availability Mode (`enable_ha_nat_gateways = true`)

- One NAT Gateway per availability zone
- Each private subnet routes to NAT in same AZ
- **Cost**: ~$32/month × number of AZs
- **Use for**: Production environments

```
Private Subnet (AZ-A) → NAT Gateway (AZ-A) → Internet
Private Subnet (AZ-B) → NAT Gateway (AZ-B) → Internet
Private Subnet (AZ-C) → NAT Gateway (AZ-C) → Internet
```

### Single NAT Mode (`enable_ha_nat_gateways = false`)

- One NAT Gateway in first availability zone
- All private subnets route through single NAT
- **Cost**: ~$32/month (fixed)
- **Use for**: Dev/Staging environments

```
Private Subnet (AZ-A) ─┐
Private Subnet (AZ-B) ─┼→ NAT Gateway (AZ-A) → Internet
Private Subnet (AZ-C) ─┘
```

## Kubernetes/EKS Integration

Subnets are automatically tagged for EKS discovery:

### Public Subnets
```hcl
"kubernetes.io/role/elb" = "1"
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"
```

### Private Subnets
```hcl
"kubernetes.io/role/internal-elb" = "1"
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"
```

These tags enable:
- Automatic ALB/NLB placement in correct subnets
- EKS cluster subnet discovery
- Load balancer controller integration

## Cost Estimation

| Component | HA Mode (3 AZ) | Single NAT |
|-----------|----------------|------------|
| NAT Gateway | ~$97/month | ~$32/month |
| Elastic IPs | ~$11/month (3×) | ~$3.65/month |
| Data Transfer | $0.045/GB | $0.045/GB |
| **Base Total** | **~$108/month** | **~$36/month** |

## Resources Created

- 1 VPC
- 1 Internet Gateway
- N Public Subnets (configurable)
- N Private Subnets (configurable)
- 1-N NAT Gateways (based on HA mode)
- 1-N Elastic IPs (based on HA mode)
- 1 Public Route Table
- N Private Route Tables (one per private subnet)
- Route Table Associations

## Related Documentation

- [Architecture Decision Records](../../../docs/DECISIONS.md)
- [Learning Journal](../../../docs/LEARNINGS.md)
- [Changelog](../../../docs/CHANGELOG.md)
- [Troubleshooting Guide](../../../docs/TROUBLESHOOTING.md)

## License

This module is part of the [production-eks-platform](https://github.com/devopsbishal/production-eks-platform) project.
