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
