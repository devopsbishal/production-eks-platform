# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2025-11-28] - Dynamic Subnet Generation & Module Documentation

### Added
- **Dynamic Subnet Generation**
  - Replaced hardcoded subnet list with `cidrsubnet()` function
  - Subnets now auto-calculated from `vpc_cidr_block` variable
  - Uses `ceil(log(n, 2))` to determine optimal subnet mask
  - Supports any VPC CIDR - subnets adjust automatically

- **Configurable Subnet Counts**
  - New `subnet_config` variable object:
    ```hcl
    subnet_config = {
      number_of_public_subnets  = 3
      number_of_private_subnets = 3
    }
    ```
  - Flexible public/private ratio (e.g., 4 public + 3 private)

- **NAT Gateway HA Toggle**
  - New `enable_ha_nat_gateways` boolean variable
  - `true`: NAT Gateway per AZ (~$96/month) - for production
  - `false`: Single NAT Gateway (~$32/month) - for dev/staging
  - Automatic routing adjustment based on mode

- **VPC Module README**
  - Comprehensive module documentation
  - Architecture diagram (ASCII art)
  - Usage examples (basic, custom, cost-optimized)
  - Input/output tables
  - Dynamic subnet calculation explanation
  - Cost estimation table

- **Locals Block for Computed Values**
  - `local.total_subnets`: Sum of public + private counts
  - `local.new_bits`: Auto-calculated subnet bits
  - `local.vpc_subnets`: Dynamically generated subnet list
  - `local.public_subnets`: Filtered public subnet map
  - `local.nat_gateway_subnets`: HA or single NAT based on toggle

### Changed
- Removed hardcoded `vpc_subnets` variable (now computed in locals)
- `availability_zones` moved to variable (was hardcoded)
- Renamed `external_traffic_cidr_block` to `internet_cidr_block`
- Updated dev environment to use custom CIDR (`192.168.0.0/16`)
- Dev now uses single NAT Gateway (`enable_ha_nat_gateways = false`)

### Technical Implementation
- **Dynamic CIDR Calculation**:
  ```hcl
  new_bits = ceil(log(local.total_subnets, 2))
  cidr_block = cidrsubnet(var.vpc_cidr_block, local.new_bits, idx)
  ```
- **AZ Distribution**: `var.availability_zones[idx % length(var.availability_zones)]`
- **Public/Private Split**: `idx < var.subnet_config.number_of_public_subnets`

### Benefits
- **Flexibility**: Change VPC CIDR without rewriting subnet configs
- **Cost Control**: Toggle HA NAT for different environments
- **Maintainability**: Single source of truth for subnet logic
- **Documentation**: Clear module README for team onboarding

---

## [2025-11-27] - NAT Gateway & Private Networking

### Added
- **NAT Gateway Infrastructure** (High Availability Setup)
  - 3 NAT Gateways (one per availability zone)
  - Each NAT Gateway deployed in corresponding public subnet
  - Elastic IPs allocated for each NAT Gateway
  - Tags include AZ identification for easy management

- **Private Route Tables**
  - Separate route table for each private subnet
  - Dynamic route configuration using advanced `for` loop with filtering
  - Routes private subnet traffic through NAT Gateway in same AZ
  - Ensures HA: Each AZ's private subnet uses its own AZ's NAT Gateway

- **Enhanced Tagging Strategy**
  - Introduced `resource_tag` variable for common tags across all resources
  - Uses `merge()` function to combine common tags with resource-specific tags
  - All resources now tagged with:
    - `ManagedBy = "Terraform"`
    - `Project = "production-eks-platform"`
    - `Environment` (dev/staging/prod)
    - Resource-specific `Name` tags

- **Kubernetes-Ready Subnet Tags**
  - Public subnets tagged with `kubernetes.io/role/elb = "1"` for ELB placement
  - Private subnets tagged with `kubernetes.io/role/internal-elb = "1"` for internal ELBs
  - All subnets tagged with `kubernetes.io/cluster/${var.environment}-eks-cluster = "shared"`

### Technical Implementation
- **NAT Gateway AZ Mapping**: Advanced for loop to match private subnets with NAT gateways by AZ
  ```hcl
  nat_gateway_id = [
    for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
    if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
  ][0]
  ```
- **Resource Naming Convention**: Improved with environment prefix and AZ suffix
- **Conditional Resource Creation**: Leveraged `for_each` with `if` filters for public/private resources

### Changed
- Renamed all resources from hyphenated names to snake_case (Terraform best practice)
  - `eks-vpc` → `eks_vpc`
  - `eks-gw` → `eks_gw`
  - `eks-subnets` → `eks_subnets`
- Subnet naming now includes type (public/private) and AZ for clarity
- Route table associations now properly separated for public vs private subnets

### Cost Considerations
- NAT Gateway costs: ~$32/month per NAT × 3 AZs = ~$96/month base cost
- Data transfer through NAT: $0.045/GB
- High availability setup chosen for production-grade architecture

### Architecture Benefits
- **Fault Tolerance**: Each AZ has independent NAT Gateway
- **No Single Point of Failure**: AZ failure doesn't affect other AZs' private subnet internet access
- **EKS Ready**: Subnet tagging enables automatic EKS integration
- **Clean Separation**: Public and private route tables completely isolated

---

## [2025-11-26] - VPC Module Foundation

### Added
- **VPC Module** (`terraform/modules/vpc/`)
  - Created reusable VPC module with parameterized configuration
  - VPC CIDR: `10.0.0.0/16` supporting ~65,000 IP addresses
  
- **Subnet Architecture**
  - 3 Public subnets across `us-west-2a`, `us-west-2b`, `us-west-2c`
    - `10.0.0.0/19` (us-west-2a)
    - `10.0.32.0/19` (us-west-2b)
    - `10.0.64.0/19` (us-west-2c)
  - 3 Private subnets across same AZs
    - `10.0.96.0/19` (us-west-2a)
    - `10.0.128.0/19` (us-west-2b)
    - `10.0.160.0/19` (us-west-2c)
  - Each subnet provides ~8,000 usable IPs (/19 CIDR)

- **Internet Gateway**
  - Created IGW for public internet access
  - Tagged as `eks-cluster-dev-gw`

- **Route Tables**
  - Public route table with `0.0.0.0/0` → Internet Gateway
  - Dynamic route table associations for public subnets only
  - Used conditional `for_each` to filter subnets based on `map_public_ip_on_launch`

- **Module Variables**
  - `vpc_cidr_block`: Configurable VPC CIDR
  - `vpc_subnets`: List of subnet objects with CIDR, AZ, and public IP settings
  - `environment`: Environment tag (dev/staging/prod)

- **Infrastructure as Code**
  - `.gitignore` for Terraform sensitive files
    - Excludes `.tfstate`, `.tfvars`, `.terraform/` directories
    - Protects AWS credentials and private keys
    - Excludes environment files and IDE configs

### Technical Decisions
- **Used `/19` subnet mask**: Provides 8,192 IPs per subnet (6 subnets from /16 VPC)
- **`for_each` with `tostring(idx)`**: Converted list indices to strings for Terraform compatibility
- **Conditional filtering**: Route tables only associate with public subnets using `if v.map_public_ip_on_launch`
- **Module-based architecture**: Enables reusability across dev/staging/prod environments

### DevOps Practices
- S3 remote state backend: `aws-eks-clusters-terraform-state`
- State file isolation per environment
- Modular design for maintainability

---