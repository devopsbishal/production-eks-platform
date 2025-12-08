# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2025-12-08] - AWS Load Balancer Controller & OIDC Provider

### Added
- **AWS Load Balancer Controller Module** (`terraform/modules/aws-load-balancer-controller/`)
  - IRSA (IAM Roles for Service Accounts) setup for secure AWS API access
  - IAM policy from official AWS source for ALB/NLB management
  - IAM role with OIDC trust policy for ServiceAccount authentication
  - Helm release for controller deployment in kube-system namespace
  - Configurable replicas (default: 2) for high availability
  - IP target type for direct pod traffic (VPC CNI optimized)

- **EKS OIDC Provider** (`terraform/modules/eks/`)
  - Added `aws_iam_openid_connect_provider` resource for IRSA support
  - Uses TLS certificate thumbprint from EKS cluster identity
  - New outputs: `oidc_provider_arn`, `oidc_provider`, `cluster_name`

- **VPC Cluster Tagging Fix**
  - Added `eks_cluster_name` variable to VPC module
  - Fixed subnet tags to use actual cluster name for ALB discovery
  - Changed empty string tags `""` to `null` for cleaner AWS tags

- **Helm Provider Configuration**
  - Added Helm provider to dev environment using EKS cluster auth
  - Uses `data.aws_eks_cluster_auth` for temporary token authentication
  - No kubeconfig file required (CI/CD friendly)

- **Test Manifests** (`test-manifest/`)
  - `deployment.yaml` - nginx test deployment
  - `service.yaml` - ClusterIP service
  - `ingress.yaml` - ALB Ingress with annotations

### Changed
- VPC module now requires `eks_cluster_name` input
- Dev environment uses locals for cluster name consistency
- Subnet tags now correctly reference the EKS cluster name

### Technical Implementation
```hcl
# IRSA Setup
resource "aws_iam_role" "alb_controller" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# Helm Release
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  # ...
}
```

### Benefits
- **Ingress Support**: Create ALBs from Kubernetes Ingress resources
- **Modern Architecture**: IRSA instead of node IAM roles
- **Secure**: Least privilege with specific ServiceAccount
- **Production Ready**: HA controller deployment with 2 replicas

---

## [2025-12-04] - Dynamic AZ Fetching & Validation

### Added
- **Dynamic AZ Fetching from AWS**
  - Uses `data.aws_availability_zones` to auto-fetch available AZs
  - Module now works in any region without hardcoded AZs
  - Falls back to data source when `var.availability_zones` is null

- **AZ Validation**
  - Validates user-provided AZs exist in the current region
  - Clear error message during `terraform plan` if invalid AZs passed
  - Uses `tobool()` trick for runtime validation with descriptive errors

- **New `az_count` Variable**
  - Controls how many AZs to use (default: 3)
  - Works with both user-provided and auto-fetched AZs
  - Uses `min()` to prevent exceeding available AZs

### Changed
- Renamed `total_number_of_az` to `az_count` (cleaner naming)
- `availability_zones` variable now defaults to `null` (triggers auto-fetch)
- Refactored locals for better readability:
  - `az_source`: Determines where AZs come from
  - `availability_zones`: Final list limited by `az_count`

### Technical Implementation
```hcl
# Validate AZs are available in region
invalid_azs = var.availability_zones != null ? [
  for az in var.availability_zones : az
  if !contains(data.aws_availability_zones.available.names, az)
] : []

# Hybrid AZ source (user-provided or AWS-fetched)
az_source = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available.names
availability_zones = slice(local.az_source, 0, min(var.az_count, length(local.az_source)))
```

### Benefits
- **Region-Agnostic**: Deploy to any region without code changes
- **Validation**: Catch invalid AZ errors at plan time, not apply time
- **Flexibility**: Override AZs when needed, auto-fetch when not
- **Cleaner Code**: Better variable names and separated logic

---

## [2025-12-01] - EKS Module & Access Management

### Added
- **EKS Module** (`terraform/modules/eks/`)
  - EKS Cluster with API authentication mode
  - Managed Node Groups with configurable scaling
  - Cluster IAM role with `AmazonEKSClusterPolicy`
  - Node group IAM role with worker policies
  - Full control plane logging (api, audit, authenticator, controllerManager, scheduler)
  - Public + private endpoint access

- **Access Entries for API Authentication**
  - `aws_eks_access_entry` resource for IAM principal mapping
  - `aws_eks_access_policy_association` for fine-grained permissions
  - Support for cluster-wide or namespace-scoped access
  - Available policies: ClusterAdmin, Admin, Edit, View

- **Configurable Node Groups**
  - `node_group_scaling_config`: desired, min, max sizes
  - `node_group_instance_types`: List of EC2 instance types
  - `node_group_capacity_type`: ON_DEMAND or SPOT support
  - `node_group_update_config`: Rolling update settings

- **EKS Module Documentation**
  - Comprehensive README with architecture diagram
  - Usage examples (basic, production, cost-optimized)
  - Input/output tables with all variables
  - Access management explanation
  - Cost estimation tables
  - Troubleshooting guide

- **Dev Environment EKS Integration**
  - `terraform.tfvars` for sensitive access entries (gitignored)
  - `terraform.tfvars.example` template for others
  - `variables.tf` with `eks_access_entries` variable

### Technical Implementation
- **API Authentication Mode** (modern approach, not ConfigMap)
- **Access Entry Pattern**:
  ```hcl
  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::ACCOUNT_ID:user/USERNAME"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }
  ```
- **Dynamic Access Entries**: Uses `for_each` over `var.access_entries` map
- **Implicit Dependencies**: Node group depends on IAM policy attachments

### Benefits
- **Modern Auth**: API mode for better AWS Console/CLI/Terraform management
- **Cost Flexibility**: SPOT instances for dev, ON_DEMAND for production
- **Security**: Sensitive credentials in gitignored tfvars
- **Observability**: All control plane logs enabled

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