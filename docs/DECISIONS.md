# Architecture Decision Records (ADRs)

This document records important architectural and technical decisions made during the project development.

---

## ADR-001: VPC CIDR Block Selection

**Date**: November 26, 2025  
**Status**: Accepted  
**Decision Makers**: Bishal

### Context
Need to choose an appropriate CIDR block for the VPC that will host an EKS cluster.

### Decision
Use `10.0.0.0/16` as the VPC CIDR block.

### Rationale
- **65,536 IP addresses** available
- Standard RFC 1918 private address space
- `/16` is AWS recommended for production VPCs
- Sufficient for large-scale EKS deployments
- Allows for future growth without re-architecture

### Alternatives Considered
1. `10.0.0.0/24` - Too small (only 256 IPs)
2. `10.0.0.0/8` - Unnecessarily large, wastes address space
3. `192.168.0.0/16` - Often conflicts with home/office networks

### Consequences
- Positive: Ample IP space for growth
- Positive: Standard pattern, easy to understand
- Negative: Cannot use this range in peered VPCs (must use non-overlapping CIDRs)

---

## ADR-002: Subnet Division Strategy

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Need to divide VPC into subnets for public and private resources across multiple availability zones.

### Decision
- 6 total subnets using `/19` CIDR masks
- 3 public subnets (one per AZ: us-west-2a, us-west-2b, us-west-2c)
- 3 private subnets (one per AZ: us-west-2a, us-west-2b, us-west-2c)
- Each subnet has ~8,000 usable IPs

### Rationale
- **High Availability**: Multi-AZ deployment protects against AZ failures
- **Separation of Concerns**: Public subnets for load balancers, private for worker nodes
- **EKS Best Practice**: AWS recommends minimum 3 AZs for production clusters
- **IP Space**: 8,000 IPs per subnet sufficient for hundreds of pods per node
- **Future-proof**: Room for additional subnet types (database, cache, etc.)

### Subnet Allocation
```
Public:  10.0.0.0/19, 10.0.32.0/19, 10.0.64.0/19
Private: 10.0.96.0/19, 10.0.128.0/19, 10.0.160.0/19
Reserved: 10.0.192.0/18 (for future use - database tier, etc.)
```

### Alternatives Considered
1. **2 AZs only** - Less resilient, not recommended for production
2. **Larger subnets (/18)** - Wastes IPs, fewer subnet options
3. **Smaller subnets (/20)** - Only 4,000 IPs, might need expansion
4. **Flat network (no private subnets)** - Security risk

### Consequences
- Positive: Production-grade HA architecture
- Positive: Security isolation
- Positive: Aligns with EKS requirements
- Negative: Requires NAT Gateways for private subnet internet access (added cost)

---

## ADR-003: Terraform Module Structure

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Need to organize Terraform code for maintainability and reusability across multiple environments.

### Decision
Use a modular structure:
```
terraform/
├── modules/          # Reusable modules
│   ├── vpc/
│   ├── eks/
│   └── ec2/
└── environments/     # Environment-specific configs
    ├── dev/
    ├── staging/
    └── prod/
```

### Rationale
- **DRY Principle**: Write VPC code once, reuse across environments
- **Separation**: Modules are generic, environments customize them
- **Testability**: Can test modules independently
- **Team Collaboration**: Clear boundaries for changes
- **Industry Standard**: Common pattern in enterprise Terraform

### Alternatives Considered
1. **Workspaces only** - Harder to customize per environment
2. **Separate repos** - Overhead of managing multiple repos
3. **Flat structure** - Code duplication, hard to maintain

### Consequences
- Positive: Easy to add new environments
- Positive: Changes to modules affect all environments (consistency)
- Negative: Learning curve for Terraform beginners
- Trade-off: Slight increase in initial complexity for long-term maintainability

---

## ADR-004: Using `for_each` Instead of `count`

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Need to create multiple subnets dynamically from a variable definition.

### Decision
Use `for_each` with map conversion instead of `count`.

```hcl
for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet }
```

### Rationale
- **Stable identifiers**: Resources referenced by key, not index position
- **Safer updates**: Reordering list doesn't destroy/recreate resources
- **Better state management**: Changes to one subnet don't affect others
- **Terraform best practice**: Recommended in HashiCorp docs

### Example of Risk with `count`:
```hcl
# If you remove subnet[1] from a list of 6 subnets:
# count: Destroys resources [1,2,3,4,5], recreates as [1,2,3,4] ❌
# for_each: Only destroys subnet "1", others unchanged ✅
```

### Alternatives Considered
1. **`count`** - Simpler syntax but dangerous for lists that change
2. **Static resources** - No flexibility, hard-coded subnets

### Consequences
- Positive: Production-safe resource management
- Positive: Clearer resource addressing in state
- Negative: Slightly more complex syntax with `tostring(idx)`

---

## ADR-005: Route Table Association Strategy

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Need to associate route tables only with public subnets, not private ones.

### Decision
Use conditional filtering in `for_each`:
```hcl
for_each = { for k, v in aws_subnet.subnets : k => v if v.map_public_ip_on_launch }
```

### Rationale
- **Dynamic filtering**: Automatically associates based on subnet property
- **Single source of truth**: `map_public_ip_on_launch` defines subnet type
- **Maintainable**: Adding new public subnet auto-includes in routing
- **Explicit intent**: Code clearly shows "public subnets only"

### Alternatives Considered
1. **Separate resources for each subnet** - Code duplication
2. **Hardcoded indices** - Brittle, breaks if subnets reordered
3. **Manual list of public subnet IDs** - Requires maintenance

### Consequences
- Positive: Self-documenting code
- Positive: Easy to add/remove public subnets
- Negative: Requires understanding of Terraform comprehension syntax

---

## ADR-006: List vs Map for Subnet Variables

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Should `vpc_subnets` variable be a list or map?

### Decision
Use a **list of objects** for subnet definitions.

```hcl
variable "vpc_subnets" {
  type = list(object({
    cidr_block              = string
    availability_zone       = string
    map_public_ip_on_launch = bool
  }))
}
```

### Rationale
- **Simplicity**: Easier to read and understand for beginners
- **Natural ordering**: Subnets are logically sequential
- **Less verbose**: No need to define string keys for each subnet
- **Sufficient for use case**: Don't need named subnet references yet

### When to Switch to Map
- If we need `var.vpc_subnets["public-web-1"]` type references
- If individual subnet override becomes common
- If managing subnets independently across modules

### Alternatives Considered
```hcl
# Map alternative:
variable "vpc_subnets" {
  type = map(object({...}))
  default = {
    "public-1" = { cidr_block = "10.0.0.0/19", ... }
    "public-2" = { cidr_block = "10.0.32.0/19", ... }
  }
}
```

### Consequences
- Positive: Clean, readable variable definition
- Positive: Easy to iterate with `for_each`
- Negative: May need refactor if named references become necessary
- Trade-off: Chose simplicity over potential future flexibility

---

## ADR-007: Remote State Backend Configuration

**Date**: November 26, 2025  
**Status**: Accepted  

### Context
Need to store Terraform state securely and enable collaboration.

### Decision
Use S3 backend with **S3-native state locking** (not DynamoDB):
```hcl
backend "s3" {
  bucket       = "aws-eks-clusters-terraform-state"
  key          = "dev/terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true
}
```

### Rationale
- **Security**: State file contains sensitive data (IPs, resource IDs)
- **Collaboration**: Team members can share state
- **S3-native locking**: Uses `use_lockfile = true` for built-in S3 locking (no DynamoDB needed)
- **Simpler setup**: Doesn't require separate DynamoDB table
- **Cost effective**: No additional DynamoDB costs
- **AWS Native**: Integrates with existing AWS infrastructure

### How S3 Locking Works
- Creates a `.tflock` file alongside state file (`dev/terraform.tfstate.tflock`)
- Uses S3 atomic operations for lock acquisition
- Automatically cleans up lock file when released
- Requires `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` permissions on lock file

### Alternatives Considered
1. **DynamoDB locking** - Now deprecated by Terraform, more complex setup
2. **No locking** - Risk of state corruption from concurrent operations
3. **Local state** - Not suitable for teams, no backup
4. **Terraform Cloud** - Additional cost, external dependency
5. **Git** - NEVER store state in git (security risk)

### Future Enhancement
- Enable encryption at rest with KMS
- Configure bucket lifecycle policies for old versions

### Consequences
- Positive: Production-ready state management with modern locking
- Positive: Enables team collaboration safely
- Positive: No additional AWS services required (vs DynamoDB)
- Negative: Requires S3 bucket setup before Terraform init
- Note: Different state files per environment (dev/, staging/, prod/)

---

## ADR-008: NAT Gateway High Availability Strategy

**Date**: November 27, 2025  
**Status**: Accepted  

### Context
Private subnets need internet access for pulling container images, software updates, and external API calls. Need to decide between single NAT Gateway vs multi-AZ NAT Gateway deployment.

### Decision
Deploy **3 NAT Gateways** (one per availability zone) with AZ-specific routing.

```hcl
# Each private subnet routes through NAT in same AZ
resource "aws_route_table" "eks_private_route_table" {
  for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet if !subnet.map_public_ip_on_launch }
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = [
      for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
      if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
    ][0]
  }
}
```

### Rationale
- **High Availability**: Each AZ has independent internet egress path
- **No Single Point of Failure**: AZ failure doesn't break other AZs' connectivity
- **Production Best Practice**: Recommended by AWS for critical workloads
- **EKS Requirement**: EKS nodes need reliable internet access for control plane communication
- **Performance**: Reduced cross-AZ data transfer costs and latency

### Cost-Benefit Analysis

**Option 1: Single NAT Gateway** (Cheaper)
- Cost: ~$32/month + data transfer
- Risk: Single point of failure
- Impact: All private subnets lose internet if NAT Gateway AZ fails

**Option 2: 3 NAT Gateways** (Chosen) ✅
- Cost: ~$96/month + data transfer (~$0.045/GB)
- Benefit: Fault tolerance across all AZs
- Impact: AZ failure only affects that AZ's private subnet

**Decision**: Production workload justifies the additional ~$64/month for HA

### Alternatives Considered
1. **Single NAT Gateway** - Rejected due to single point of failure
2. **NAT Instances (EC2)** - Deprecated, requires more maintenance
3. **VPC Endpoints only** - Doesn't cover all internet access needs
4. **2 NAT Gateways** - Inconsistent, doesn't match 3-AZ architecture

### Technical Implementation
- Used advanced `for` loop with conditional filtering to match NAT by AZ
- `[0]` extraction pattern to convert single-item list to scalar value
- Dynamic routing ensures each private subnet uses correct NAT Gateway

### Consequences
- Positive: Production-grade fault tolerance
- Positive: No cross-AZ dependency for internet access
- Positive: Better performance (traffic stays in same AZ)
- Negative: Higher monthly cost (~$96 vs ~$32)
- Negative: More complex Terraform logic for AZ matching
- Trade-off: Chose reliability over cost optimization

---

## ADR-009: Dynamic Subnet Generation with `cidrsubnet()`

**Date**: November 28, 2025  
**Status**: Accepted  

### Context
Hardcoded subnet CIDRs in variables become a maintenance burden and don't adapt when VPC CIDR changes. Need a more dynamic approach.

### Decision
Use Terraform's `cidrsubnet()` function with `locals` block to dynamically generate subnets.

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

### Rationale
- **Single Source of Truth**: VPC CIDR defines everything
- **Automatic Calculation**: `ceil(log(n, 2))` finds optimal subnet bits
- **Flexibility**: Change counts without recalculating CIDRs
- **Reusability**: Same module works for any VPC CIDR
- **No Variable Dependencies**: Workaround for Terraform's limitation (variables can't reference other variables)

### How `cidrsubnet()` Works
```hcl
cidrsubnet(prefix, newbits, netnum)
# prefix:  Base CIDR ("10.0.0.0/16")
# newbits: Bits to add (3 = /16 → /19)
# netnum:  Which subnet (0, 1, 2, ...)

cidrsubnet("10.0.0.0/16", 3, 0) = "10.0.0.0/19"
cidrsubnet("10.0.0.0/16", 3, 1) = "10.0.32.0/19"
```

### Alternatives Considered
1. **Hardcoded subnet list** - Rejected: Maintenance burden, doesn't adapt
2. **External CIDR calculator** - Rejected: Extra tooling required
3. **Map variable with named subnets** - Rejected: More verbose, still hardcoded

### Consequences
- Positive: Module works with any valid VPC CIDR
- Positive: Adding/removing subnets only requires count change
- Positive: Consistent subnet sizing (all same /19, /20, etc.)
- Negative: All subnets same size (can't mix /19 and /24)
- Trade-off: Simplicity over fine-grained control

---

## ADR-010: NAT Gateway HA Toggle Variable

**Date**: November 28, 2025  
**Status**: Accepted  

### Context
Different environments have different requirements:
- **Production**: Needs high availability (NAT per AZ)
- **Dev/Staging**: Can tolerate single NAT to save costs

### Decision
Add `enable_ha_nat_gateways` boolean variable to toggle between modes.

```hcl
variable "enable_ha_nat_gateways" {
  description = "Enable NAT Gateway per AZ for HA"
  type        = bool
  default     = true
}

locals {
  nat_gateway_subnets = var.enable_ha_nat_gateways ? local.public_subnets : {
    "0" = local.public_subnets["0"]
  }
}
```

### Rationale
- **Cost Optimization**: ~$64/month savings in non-prod
- **Environment Parity**: Same module, different configs
- **Explicit Choice**: Forces conscious decision about HA
- **Simple Toggle**: Boolean is easy to understand

### Cost Impact
| Environment | Mode | NAT Gateways | Monthly Cost |
|-------------|------|--------------|-------------|
| Production  | HA   | 3            | ~$96        |
| Staging     | Single | 1          | ~$32        |
| Dev         | Single | 1          | ~$32        |

**Annual Savings**: ~$768/year for dev + staging

### Alternatives Considered
1. **Separate modules** - Rejected: Code duplication
2. **Count variable** - Rejected: Less intuitive than boolean
3. **Always HA** - Rejected: Unnecessary cost in non-prod

### Consequences
- Positive: Right-sized infrastructure per environment
- Positive: Cost visibility and control
- Positive: Same module for all environments
- Negative: Single NAT is SPOF for non-prod (acceptable risk)
- Trade-off: Cost savings vs. resilience in non-prod

---

## ADR-011: EKS API Authentication Mode

**Date**: December 1, 2025  
**Status**: Accepted  

### Context
EKS supports two authentication modes:
1. **CONFIG_MAP** (legacy): Uses `aws-auth` ConfigMap in kube-system
2. **API** (modern): Uses AWS EKS Access Entries API

### Decision
Use **API authentication mode** for all new clusters.

```hcl
access_config {
  authentication_mode = "API"
}
```

### Rationale
- **AWS Console visibility**: See access in EKS console, not just kubectl
- **CloudTrail integration**: All access changes audited
- **No cluster access needed**: Manage access even if cluster is unreachable
- **Terraform native**: Managed via `aws_eks_access_entry` resource
- **AWS recommendation**: API mode is the modern approach

### Comparison
| Feature | API Mode | ConfigMap Mode |
|---------|----------|----------------|
| Management | AWS Console/CLI/Terraform | kubectl only |
| Audit | CloudTrail | Limited |
| Recovery | AWS API always available | Need cluster access |
| Best Practice | ✅ Recommended | Legacy |

### Alternatives Considered
1. **CONFIG_MAP** - Rejected: Legacy, harder to manage
2. **API_AND_CONFIG_MAP** - Rejected: Unnecessary complexity

### Consequences
- Positive: Modern, AWS-recommended approach
- Positive: Better observability and management
- Positive: Works with Terraform access entry resources
- Negative: Requires access entries for all users (no ConfigMap fallback)
- Note: Root user cannot be added as access entry (AWS limitation)

---

## ADR-012: Managed Node Groups vs Self-Managed

**Date**: December 1, 2025  
**Status**: Accepted  

### Context
EKS offers multiple node provisioning options:
1. **Managed Node Groups**: AWS manages node lifecycle
2. **Self-Managed Nodes**: User manages EC2 Auto Scaling Groups
3. **Fargate**: Serverless, no EC2 management

### Decision
Use **Managed Node Groups** for worker nodes.

```hcl
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.subnet_ids
  capacity_type   = var.node_group_capacity_type  # ON_DEMAND or SPOT
  instance_types  = var.node_group_instance_types
  # ...
}
```

### Rationale
- **Simplified operations**: AWS handles AMI updates, draining, replacement
- **Better integration**: Native EKS console support
- **Rolling updates**: Automatic node replacement during updates
- **Cost flexibility**: Supports both ON_DEMAND and SPOT
- **Less Terraform code**: No ASG, launch template management

### Alternatives Considered
1. **Self-Managed ASG** - Rejected: More operational overhead
2. **Fargate** - Rejected: Less control, different pricing model
3. **Karpenter** - Planned for future (Phase 4)

### Consequences
- Positive: Reduced operational burden
- Positive: Native AWS support and updates
- Positive: Simpler Terraform configuration
- Negative: Less customization than self-managed
- Future: Will add Karpenter for advanced autoscaling

---

## ADR-013: SPOT Instances for Non-Production

**Date**: December 1, 2025  
**Status**: Accepted  

### Context
Node group costs are significant portion of EKS spending. Need to optimize for different environments.

### Decision
Use SPOT instances for dev/staging, ON_DEMAND for production.

```hcl
variable "node_group_capacity_type" {
  type        = string
  description = "ON_DEMAND or SPOT"
  default     = "SPOT"  # Cost-optimized default
}
```

### Cost Comparison (4 × t3.medium nodes)
| Capacity Type | Hourly | Monthly |
|--------------|--------|--------|
| ON_DEMAND | $0.17 | ~$120 |
| SPOT | ~$0.05 | ~$36 |
| **Savings** | 70% | ~$84/mo |

### Rationale
- **Dev/Staging**: Can tolerate interruptions
- **70% savings**: Significant cost reduction
- **Multiple instance types**: Improves SPOT availability
- **Managed Node Groups**: Handle SPOT interruptions gracefully

### Risk Mitigation
- Use multiple instance types: `["t3.medium", "t3.large"]`
- Set `min_size >= 2` for basic availability
- Production always uses ON_DEMAND

### Alternatives Considered
1. **Always ON_DEMAND** - Rejected: Wasteful for non-prod
2. **Reserved Instances** - Considered for stable prod workloads
3. **Savings Plans** - Considered for committed usage

### Consequences
- Positive: ~70% cost savings in dev/staging
- Positive: Same module, different capacity_type
- Negative: SPOT can be interrupted (acceptable for non-prod)
- Trade-off: Cost vs. stability (appropriate per environment)

---

## ADR-014: Gitignored tfvars for Sensitive Data

**Date**: December 1, 2025  
**Status**: Accepted  

### Context
EKS access entries contain AWS account IDs and IAM principal ARNs. These shouldn't be committed to git.

### Decision
Use gitignored `terraform.tfvars` with a committed example template.

**File Structure**:
```
terraform/environments/dev/
├── main.tf                    # ✅ Committed
├── variables.tf               # ✅ Committed
├── terraform.tfvars           # ❌ Gitignored (real values)
└── terraform.tfvars.example   # ✅ Committed (template)
```

**terraform.tfvars.example**:
```hcl
eks_access_entries = {
  admin = {
    principal_arn = "arn:aws:iam::ACCOUNT_ID:user/USERNAME"
  }
}
```

### Rationale
- **Security**: Account IDs and ARNs not in git history
- **Collaboration**: Example file shows required format
- **Already gitignored**: `.gitignore` already excludes `*.tfvars`
- **Local overrides**: Each developer has own credentials

### Alternatives Considered
1. **Hardcoded placeholders** - Rejected: Must remember to change
2. **Environment variables** - Rejected: Complex for nested objects
3. **AWS Secrets Manager** - Overkill for this use case
4. **Terraform Cloud variables** - Adds external dependency

### Consequences
- Positive: Sensitive data never committed
- Positive: Clear example for team members
- Positive: Leverages existing gitignore patterns
- Negative: Extra file to maintain
- Note: Document in README to copy example file

---

## ADR-015: Dynamic AZ Fetching with Validation

**Date**: December 4, 2025  
**Status**: Accepted  

### Context
Hardcoded availability zones limit module portability across regions. Need a way to:
1. Auto-fetch AZs when not specified
2. Validate user-provided AZs exist in the region
3. Control how many AZs to use

### Decision
Use `data.aws_availability_zones` with hybrid logic and runtime validation.

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Validate user AZs exist
  invalid_azs = var.availability_zones != null ? [
    for az in var.availability_zones : az
    if !contains(data.aws_availability_zones.available.names, az)
  ] : []

  validate_azs = length(local.invalid_azs) > 0 ? tobool(
    "ERROR: Invalid AZs: ${join(", ", local.invalid_azs)}"
  ) : true

  # Hybrid source
  az_source = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available.names
  availability_zones = slice(local.az_source, 0, min(var.az_count, length(local.az_source)))
}
```

### Rationale
- **Region-agnostic**: Module works in any AWS region
- **Fail-fast**: Invalid AZs caught at plan time
- **Flexibility**: Override when needed, auto-fetch otherwise
- **Clear errors**: `tobool()` trick provides descriptive error messages

### Alternatives Considered
1. **Always hardcode AZs** - Rejected: Not portable
2. **Variable validation block** - Rejected: Can't access data sources
3. **No validation** - Rejected: Errors would occur at apply time

### Consequences
- Positive: Deploy same code to any region
- Positive: Early error detection for invalid AZs
- Positive: Cleaner module interface
- Negative: Requires AWS API call during plan (acceptable)


---

## ADR-016: AWS Load Balancer Controller Deployment Strategy

**Date**: December 8, 2025  
**Status**: Accepted  

### Context
Need to enable Ingress resources in EKS to create AWS Application Load Balancers. Multiple approaches available:
1. In-tree cloud provider (legacy, limited)
2. NGINX Ingress Controller
3. AWS Load Balancer Controller

### Decision
Use **AWS Load Balancer Controller** deployed via Helm with IRSA for authentication.

```hcl
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
}
```

### Rationale
- **Native AWS Integration**: Creates ALBs/NLBs directly, no extra hop
- **IP Target Type**: Direct traffic to pods (faster than instance mode)
- **Feature Rich**: WAF, Cognito, redirects, weighted routing
- **AWS Recommended**: Official controller from AWS
- **Active Development**: Regular updates and improvements

### Alternatives Considered
1. **In-tree cloud provider** - Rejected: Only creates CLB/basic NLB, no ALB support
2. **NGINX Ingress Controller** - Rejected: Extra hop through NGINX pods, more resources
3. **Traefik/Kong** - Rejected: More complex, overkill for current needs

### Consequences
- Positive: Native ALB creation from Ingress resources
- Positive: Better performance with IP targets
- Positive: Full ALB feature support
- Negative: Requires OIDC provider setup for IRSA
- Negative: Subnet tagging required for ALB discovery

---

## ADR-017: IRSA for AWS Load Balancer Controller

**Date**: December 8, 2025  
**Status**: Accepted  

### Context
AWS Load Balancer Controller needs AWS API access to create/manage ALBs. Two main approaches:
1. Node IAM role (all pods get same permissions)
2. IRSA (pod-specific IAM roles via ServiceAccount)

### Decision
Use **IRSA (IAM Roles for Service Accounts)** for controller authentication.

```hcl
resource "aws_iam_role" "alb_controller" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}
```

### Rationale
- **Least Privilege**: Only the controller pod gets ALB permissions
- **Security**: Other pods don't inherit node-level permissions
- **Audit Trail**: IAM role usage logged in CloudTrail
- **Best Practice**: AWS recommended approach for EKS workloads
- **Credential Rotation**: Tokens auto-rotate (no long-lived credentials)

### How IRSA Works
```
ServiceAccount (annotated) → OIDC Provider → STS AssumeRoleWithWebIdentity → IAM Role
```

### Alternatives Considered
1. **Node IAM Role** - Rejected: All pods get permissions, security risk
2. **kube2iam/kiam** - Rejected: Deprecated, replaced by IRSA
3. **Static credentials** - Rejected: Security anti-pattern

### Consequences
- Positive: Secure, least-privilege access
- Positive: Native AWS integration
- Positive: No credential management needed
- Negative: Requires OIDC provider (added in this change)
- Negative: More Terraform resources to manage

---

## ADR-018: Helm Provider for Kubernetes Resources

**Date**: December 8, 2025  
**Status**: Accepted  

### Context
Need to deploy AWS Load Balancer Controller to EKS. Options:
1. kubectl/Kubernetes manifests
2. Helm CLI (outside Terraform)
3. Helm Provider in Terraform
4. kubernetes_manifest resources

### Decision
Use **Helm Provider** in Terraform for Kubernetes application deployment.

```hcl
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
```

### Rationale
- **Single Source of Truth**: Infrastructure + apps in Terraform
- **Reproducible**: Same deployment every time
- **CI/CD Friendly**: No manual helm commands needed
- **Version Controlled**: Chart versions pinned in code
- **Dependency Management**: `depends_on` ensures correct ordering

### Authentication Strategy
- Uses `aws_eks_cluster_auth` data source for temporary tokens
- No kubeconfig file required
- Works in CI/CD pipelines without local setup

### Alternatives Considered
1. **Helm CLI** - Rejected: Manual step, not in Terraform state
2. **kubernetes_manifest** - Rejected: Too verbose for Helm charts
3. **ArgoCD** - Future: Will add for application deployments

### Consequences
- Positive: Everything managed through Terraform
- Positive: Works in CI/CD without kubeconfig
- Positive: Clear dependency ordering
- Negative: Requires Helm provider configuration per environment
- Note: Provider configured in environment, not module

---

## ADR-019: VPC Subnet Tagging for ALB Discovery

**Date**: December 8, 2025  
**Status**: Accepted  

### Context
AWS Load Balancer Controller auto-discovers subnets for ALB placement using Kubernetes tags. Without proper tags, ALB creation fails.

### Decision
Add required tags to VPC subnets and pass cluster name as variable.

```hcl
# Public subnets (internet-facing ALB)
tags = {
  "kubernetes.io/role/elb"                    = "1"
  "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
}

# Private subnets (internal ALB)
tags = {
  "kubernetes.io/role/internal-elb"           = "1"
  "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
}
```

### Rationale
- **Auto-discovery**: Controller finds subnets without manual specification
- **Multi-cluster Support**: `shared` allows multiple clusters to use same subnets
- **Role Separation**: `elb` vs `internal-elb` distinguishes internet-facing vs internal
- **Cluster Association**: Tag identifies which cluster can use the subnet

### Tag Meanings
| Tag | Value | Purpose |
|-----|-------|---------|
| `kubernetes.io/role/elb` | `1` | Internet-facing ALB placement |
| `kubernetes.io/role/internal-elb` | `1` | Internal ALB placement |
| `kubernetes.io/cluster/<name>` | `shared` or `owned` | Cluster association |

### Previous Issue
Subnet tag used wrong cluster name pattern:
```hcl
# Before (wrong)
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"  # dev-eks-cluster

# After (correct)
"kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"  # eks-cluster-dev
```

### Consequences
- Positive: ALB Controller discovers subnets automatically
- Positive: Consistent with AWS documentation
- Positive: Explicit cluster name prevents mismatches
- Negative: Requires `eks_cluster_name` input to VPC module
- Trade-off: Added coupling between VPC and EKS (acceptable for EKS-focused VPC)

---

## ADR-020: Subdomain Delegation for Route53

**Date**: December 9, 2025  
**Status**: Accepted  

### Context
Need DNS management for EKS services. Primary domain is managed in Cloudflare.

### Decision
Delegate a subdomain (`eks.rentalhubnepal.com`) to Route53 instead of migrating the entire domain.

### Rationale
- **Keep existing DNS provider**: No disruption to existing services
- **Separation of concerns**: AWS resources use Route53, other records stay in Cloudflare
- **Cost effective**: Only pay for AWS DNS records
- **External DNS compatible**: Route53 is natively supported
- **Security**: Cloudflare proxy/security features remain for main domain

### Implementation
1. Create Route53 hosted zone for subdomain
2. Add NS records in Cloudflare pointing to Route53 name servers
3. External DNS manages records within the subdomain

### Alternatives Considered
1. **Migrate entire domain to Route53** - Disrupts existing setup, loses Cloudflare features
2. **Use Cloudflare as External DNS provider** - Less AWS integration, requires API tokens
3. **Manual DNS management** - Error-prone, doesn't scale

### Consequences
- Positive: Non-disruptive integration
- Positive: Best of both worlds (Cloudflare + Route53)
- Positive: Works with External DNS out of the box
- Negative: Requires manual NS record setup in Cloudflare
- Negative: DNS propagation delay during initial setup

---

## ADR-021: External DNS for Automatic DNS Management

**Date**: December 9, 2025  
**Status**: Accepted  

### Context
Need automatic DNS record management for Kubernetes Ingress resources.

### Decision
Deploy External DNS with IRSA using Terraform Helm provider.

### Configuration Choices

| Setting | Value | Reason |
|---------|-------|--------|
| `provider` | `aws` | Route53 integration |
| `policy` | `sync` | Full lifecycle management (create/update/delete) |
| `sources` | `ingress`, `service` | Watch both resource types |
| `domainFilters` | `eks.rentalhubnepal.com` | Limit scope to subdomain |
| `txtOwnerId` | `<cluster-name>` | Prevent multi-cluster conflicts |
| `txtPrefix` | `external-dns-` | Clear ownership identification |

### IRSA Pattern (Same as ALB Controller)
```
Ingress Annotation → External DNS Pod → IRSA → IAM Role → Route53 API
```

### Alternatives Considered
1. **Manual DNS management** - Error-prone, slow
2. **cert-manager DNS solver** - Only for certificate validation, not general DNS
3. **Custom controller** - Unnecessary complexity

### Consequences
- Positive: Zero-touch DNS management
- Positive: Declarative (DNS as code via Ingress annotations)
- Positive: Automatic cleanup when Ingress deleted
- Negative: Learning curve for annotation syntax
- Negative: Requires Route53 hosted zone (not free tier)

---

## ADR-022: Terraform vs GitOps for Kubernetes Add-ons

**Date**: December 9, 2025  
**Status**: Accepted (Temporary)  

### Context
Choosing deployment method for Kubernetes add-ons (ALB Controller, External DNS).

### Decision
Use Terraform Helm provider for now. Plan to migrate to GitOps (ArgoCD) later.

### Rationale
- **Learning path**: Build understanding of each component first
- **Single tool**: Consistent workflow with infrastructure
- **IRSA integration**: IAM resources and Helm releases in same codebase
- **Future flexibility**: Can refactor to GitOps when ready

### Hybrid Best Practice (Future State)
| Layer | Tool | Reason |
|-------|------|--------|
| Infrastructure | Terraform | Rarely changes, state-managed |
| IAM/IRSA | Terraform | Security boundaries |
| K8s Add-ons | ArgoCD | Frequent updates, GitOps flow |
| Applications | ArgoCD | Developer self-service |

### Migration Path
1. ✅ Phase 1 (Current): Terraform manages everything
2. ⏳ Phase 2: Add ArgoCD via Terraform
3. ⏳ Phase 3: Move add-ons to ArgoCD ApplicationSets
4. ⏳ Phase 4: Full GitOps for K8s layer

### Consequences
- Positive: Simpler learning path
- Positive: Complete infrastructure in one place
- Negative: Terraform needs cluster access during apply
- Trade-off: Will require refactoring later (acceptable for learning)

---
