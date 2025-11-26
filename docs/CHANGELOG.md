# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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