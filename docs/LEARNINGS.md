# Learning Journal

This document tracks key learnings, insights, and "aha moments" throughout the project.

---

## December 9, 2025 - External DNS & Route53

### 🌐 Subdomain Delegation Pattern

**Problem**: How to use Route53 for EKS DNS without migrating entire domain from Cloudflare?

**Learning**: 
Subdomain delegation allows you to "hand off" a subdomain to a different DNS provider.

**How it works**:
```
rentalhubnepal.com (Cloudflare)
    └── NS record: eks → Route53 name servers

eks.rentalhubnepal.com (Route53)
    └── A record: app.eks.rentalhubnepal.com → ALB IP
```

**Key insight**: NS records in Cloudflare tell DNS resolvers "for anything under `eks.*`, ask Route53 instead."

---

### 🔄 External DNS vs Route53 Zone

**Question**: "If External DNS manages DNS automatically, why create Route53 zone module?"

**Learning**:
External DNS can only manage **records** within an existing zone, not create zones.

| Component | Responsibility |
|-----------|---------------|
| Route53 Zone Module | Creates the hosted zone container |
| External DNS | Creates/updates/deletes A/CNAME/TXT records inside |

**Analogy**: Route53 zone is the filing cabinet, External DNS is the person who files documents.

---

### 📝 Helm `set` Syntax for Nested Values

**Problem**: How to set environment variables in Helm via Terraform?

**Wrong approach** (doesn't work):
```hcl
set = [{
  name = "env"
  value = [{ name = "AWS_REGION", value = "us-west-2" }]
}]
```

**Correct approach** (use array indexing):
```hcl
set = [
  { name = "env[0].name",  value = "AWS_REGION" },
  { name = "env[0].value", value = "us-west-2" }
]
```

**Key insight**: Helm's `--set` syntax uses dot notation and array indices, not nested structures.

---

### 🏷️ External DNS Annotations

**Learning**: External DNS uses annotations to know what DNS records to create.

**Key annotations**:
```yaml
annotations:
  # Tell External DNS what hostname to create
  external-dns.alpha.kubernetes.io/hostname: app.eks.example.com
  
  # Optional: Set TTL for the record
  external-dns.alpha.kubernetes.io/ttl: "300"
```

**Important**: The `host` field in Ingress rules should match the hostname annotation.

---

### 🔐 TXT Ownership Records

**Problem**: How does External DNS know which records it created vs manual records?

**Learning**: External DNS creates TXT records alongside A/CNAME records to track ownership.

```
app.eks.example.com              A       1.2.3.4
external-dns-app.eks.example.com TXT     "heritage=external-dns,external-dns/owner=eks-cluster-dev"
```

**`txtOwnerId`**: Unique identifier (usually cluster name) prevents one cluster's External DNS from modifying another cluster's records.

---

### 🤔 Terraform vs GitOps for K8s Add-ons

**Question**: Is deploying Helm charts via Terraform a good practice?

**Learning**: It's a trade-off.

| Approach | Best For |
|----------|----------|
| Terraform Helm | Infrastructure-coupled add-ons, IRSA setup, learning |
| GitOps (ArgoCD) | Frequent updates, developer self-service, production |

**Hybrid pattern** (production best practice):
- Terraform: IAM roles, Route53 zones, OIDC provider
- ArgoCD: Helm releases, application deployments

**For learning**: Terraform is fine. Refactor to GitOps when ready.

---

## December 8, 2025 - AWS Load Balancer Controller & IRSA

### 🔐 IRSA (IAM Roles for Service Accounts)

**What is IRSA?**
A way for Kubernetes pods to assume IAM roles without using node-level permissions.

**The Flow**:
```
Pod → ServiceAccount (annotated) → OIDC Provider → STS → IAM Role → AWS Permissions
```

**Key Components**:
1. **OIDC Provider**: Bridge between Kubernetes and AWS IAM
2. **IAM Role**: Trust policy allows ServiceAccount to assume role
3. **ServiceAccount**: Annotated with IAM role ARN
4. **Pod**: Uses ServiceAccount, gets temporary AWS credentials

**Implementation**:
```hcl
# 1. OIDC Provider (in EKS module)
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

# 2. IAM Role with OIDC trust
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

# 3. Helm annotates ServiceAccount
set = [{
  name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
  value = aws_iam_role.alb_controller.arn
  type  = "string"
}]
```

**Why IRSA over Node IAM Role?**
- **Least Privilege**: Only specific pods get specific permissions
- **Security**: Other pods can't access ALB controller's permissions
- **Audit**: CloudTrail shows which ServiceAccount used the role

---

### 🎯 Helm Provider Authentication (Without kubeconfig)

**Problem**: Helm needs cluster access, but we don't want to depend on local kubeconfig.

**Solution**: Use EKS data sources for authentication:
```hcl
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
```

**Key Insight**: `aws_eks_cluster_auth` returns a **temporary token** (15 min) that's:
- Not stored in state
- Auto-refreshed on each Terraform run
- Based on your AWS credentials (not kubeconfig)

**Benefits**:
- Works in CI/CD without kubeconfig setup
- No long-lived credentials
- Uses existing AWS auth

---

### 🏷️ Kubernetes Subnet Tags for ALB Discovery

**The Problem**:
```
Error: couldn't auto-discover subnets: unable to resolve at least one subnet
```

**Root Cause**: ALB Controller needs specific tags to find subnets.

**Required Tags**:
| Tag | Value | Used For |
|-----|-------|----------|
| `kubernetes.io/role/elb` | `1` | Internet-facing ALB |
| `kubernetes.io/role/internal-elb` | `1` | Internal ALB |
| `kubernetes.io/cluster/<name>` | `shared` | Cluster association |

**My Mistake**:
```hcl
# Wrong - cluster name pattern didn't match actual cluster
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"  # dev-eks-cluster

# Actual cluster name was: eks-cluster-dev
```

**Fix**: Pass actual cluster name to VPC module:
```hcl
module "dev-vpc" {
  source           = "../../modules/vpc"
  eks_cluster_name = local.eks_cluster_name  # "eks-cluster-dev"
}
```

**Key Insight**: Subnet tags MUST match the actual EKS cluster name exactly!

---

### 📦 Helm `set` Block Syntax Evolution

**Old syntax** (deprecated):
```hcl
set {
  name  = "key"
  value = "value"
}
```

**New syntax** (Helm provider 2.x+):
```hcl
set = [
  {
    name  = "key"
    value = "value"
  },
  {
    name  = "another.key"
    value = "another-value"
    type  = "string"  # For values with special characters
  }
]
```

**When to use `type = "string"`**:
- Values with special characters (dots, slashes)
- Annotation keys like `eks.amazonaws.com/role-arn`

---

### 🆚 AWS LB Controller vs NGINX Ingress Controller

**Confusion**: Do I need NGINX Ingress Controller?

**Answer**: No! They serve similar purposes but work differently:

| Aspect | AWS LB Controller | NGINX Ingress |
|--------|-------------------|---------------|
| Load Balancer | AWS ALB (native) | NLB → NGINX pod |
| Traffic Path | User → ALB → Pod | User → NLB → NGINX → Pod |
| Resources | AWS managed | NGINX pods in cluster |
| Features | ALB native (WAF, Cognito) | NGINX native (rate limit, rewrites) |
| Cost | ALB pricing | NLB + EC2 for NGINX pods |

**Choose AWS LB Controller when**:
- You want native AWS integration
- ALB features are sufficient
- Fewer moving parts preferred

**Choose NGINX when**:
- Need NGINX-specific features
- Multi-cloud portability needed
- Already familiar with NGINX

---

### 💡 Key Patterns Learned Today

1. **IRSA = Pod-level IAM** - ServiceAccount + OIDC + IAM Role
2. **Helm auth without kubeconfig** - Use EKS data sources
3. **Subnet tagging critical** - Exact cluster name match required
4. **`type = "string"`** - For Helm values with special chars
5. **AWS LB Controller ≠ NGINX** - Different approaches, same goal
6. **Provider in environment** - Not in module (for flexibility)

---

## December 4, 2025 - Dynamic AZ & Runtime Validation

### 🌍 Auto-Fetching Availability Zones

**Problem**: Hardcoded AZs make module region-specific.

**Solution**: Use `data.aws_availability_zones` data source.

```hcl
data "aws_availability_zones" "available" {
  state = "available"  # Only get currently available AZs
}

# Use: data.aws_availability_zones.available.names
# Returns: ["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d"]
```

**Key Insight**: `state = "available"` filters out AZs that are temporarily unavailable!

---

### 🔀 Hybrid Variable Pattern

**Problem**: Want to auto-fetch by default, but allow override.

**Solution**: Default to `null`, use ternary in locals.

```hcl
variable "availability_zones" {
  type    = list(string)
  default = null  # null triggers auto-fetch
}

locals {
  az_source = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available.names
}
```

**Pattern**:
- `null` = "not provided" → use data source
- `["us-east-1a", ...]` = "provided" → use user's list

---

### ✅ Runtime Validation with `tobool()` Trick

**Problem**: Variable validation can't access data sources.

**Solution**: Use `tobool("error message")` in locals.

```hcl
locals {
  invalid_azs = var.availability_zones != null ? [
    for az in var.availability_zones : az
    if !contains(data.aws_availability_zones.available.names, az)
  ] : []

  validate_azs = length(local.invalid_azs) > 0 ? tobool(
    "ERROR: Invalid AZs: ${join(", ", local.invalid_azs)}"
  ) : true
}
```

**How it works**:
1. If invalid AZs found → `tobool("error string")` fails
2. Terraform shows the string as the error message!
3. If all valid → returns `true` (no error)

**Error output**:
```
Error: Invalid function argument
cannot convert "ERROR: Invalid AZs: us-east-1a, us-east-1b" to bool
```

---

### 📐 The `min()` Safety Pattern

**Problem**: User might request more AZs than available.

**Solution**: Use `min()` to cap the count.

```hcl
availability_zones = slice(local.az_source, 0, min(var.az_count, length(local.az_source)))
```

**Example**:
- `az_count = 5`, but only 4 AZs available
- `min(5, 4) = 4` → uses 4 AZs, no error

---

### 🏷️ Better Variable Naming

**Renamed**: `total_number_of_az` → `az_count`

**Why**:
- Shorter, cleaner
- Matches common conventions (`instance_count`, `replica_count`)
- Easier to type and remember

**Refactored locals**:
```hcl
# Before (one long line)
availability_zones = var.availability_zones != null ? slice(var.availability_zones, 0, min(...)) : slice(data...)

# After (split into steps)
az_source = var.availability_zones != null ? var.availability_zones : data...names
availability_zones = slice(local.az_source, 0, min(var.az_count, length(local.az_source)))
```

**Key Insight**: Break complex expressions into named intermediate values!

---

### 💡 Key Patterns Learned Today

1. **Data sources for dynamic values** - Fetch from AWS at plan time
2. **`null` default for optional override** - Trigger different behavior
3. **`tobool()` for runtime validation** - Fail with custom error message
4. **`min()` for safety caps** - Don't exceed available resources
5. **`contains()` for list membership** - Check if value in list
6. **Split complex expressions** - Named locals improve readability

---

## December 1, 2025 - EKS Module & Access Management

### 🔐 EKS Authentication Modes

**Problem**: How to grant IAM users access to EKS cluster?

**Two modes available**:

| Mode | How It Works | Management |
|------|--------------|------------|
| `CONFIG_MAP` | Edit `aws-auth` ConfigMap | kubectl only |
| `API` | Use Access Entries API | AWS Console/CLI/Terraform |

**Key Learning**: API mode is the modern approach!

```hcl
access_config {
  authentication_mode = "API"  # Recommended for new clusters
}
```

**Why API mode?**
- Manage access from AWS Console (not just kubectl)
- CloudTrail audit logging
- Works even if cluster is unreachable
- Native Terraform resources

---

### 📝 Access Entries Pattern

**Problem**: Grant multiple IAM principals access with different permission levels.

**Solution**: Map of access entries with `for_each`.

```hcl
variable "access_entries" {
  type = map(object({
    principal_arn     = string
    policy_arn        = optional(string, "...ClusterAdminPolicy")
    access_scope_type = optional(string, "cluster")
  }))
}

resource "aws_eks_access_entry" "access_entries" {
  for_each      = var.access_entries
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value.principal_arn
}
```

**Available Policies**:
- `AmazonEKSClusterAdminPolicy` - Full admin (including IAM)
- `AmazonEKSAdminPolicy` - Admin without IAM permissions
- `AmazonEKSEditPolicy` - Create/edit/delete resources
- `AmazonEKSViewPolicy` - Read-only access

**Key Insight**: Access = Entry + Policy Association (two resources!)

---

### 🚫 Root User Limitation

**Learned**: Root user CANNOT be added as EKS access entry!

**Why?**: AWS security best practice. EKS explicitly blocks root.

**Solutions**:
1. Create dedicated IAM user for console access
2. Use IAM roles (SSO, federated)
3. Enable console password for CLI user

---

### 🔗 Connecting to EKS Cluster

**Command to update kubeconfig**:
```bash
aws eks update-kubeconfig --region us-west-2 --name eks-cluster-dev
```

**Key Learning**: This MERGES with existing ~/.kube/config!
- Doesn't overwrite existing clusters
- Adds new context and sets it as current
- Use `kubectl config get-contexts` to see all

**Switch contexts**:
```bash
kubectl config use-context <context-name>
```

---

### 💰 Node Group Cost Optimization

**SPOT vs ON_DEMAND**:

| Type | Cost | Use Case |
|------|------|----------|
| ON_DEMAND | Full price | Production (reliability) |
| SPOT | ~70% cheaper | Dev/Staging (cost-saving) |

**Example (4 × t3.medium)**:
- ON_DEMAND: ~$120/month
- SPOT: ~$36/month
- **Savings**: ~$84/month (70%!)

**Best Practice**: Use multiple instance types for SPOT availability:
```hcl
node_group_instance_types = ["t3.medium", "t3.large", "t3a.medium"]
```

---

### 🛡️ Sensitive Data in Variables

**Problem**: Access entries contain account IDs (sensitive).

**Solution**: Gitignored tfvars pattern.

```
terraform/environments/dev/
├── variables.tf               # Declares variable (committed)
├── terraform.tfvars           # Real values (gitignored!)
└── terraform.tfvars.example   # Template (committed)
```

**terraform.tfvars.example**:
```hcl
eks_access_entries = {
  admin = {
    principal_arn = "arn:aws:iam::ACCOUNT_ID:user/USERNAME"
  }
}
```

**Key Insight**: Template shows format, real values stay local!

---

### 🎯 EKS IAM Role Policies

**Cluster Role** needs:
- `AmazonEKSClusterPolicy` - Core EKS operations

**Node Group Role** needs:
- `AmazonEKSWorkerNodePolicy` - Connect to EKS
- `AmazonEKS_CNI_Policy` - VPC networking
- `AmazonEC2ContainerRegistryReadOnly` - Pull images from ECR

**Pattern**: Attach policies before creating resources!

```hcl
depends_on = [
  aws_iam_role_policy_attachment.eks_cluster_role_AmazonEKSClusterPolicy,
]
```

---

### 📊 Control Plane Logging

**All log types enabled**:
```hcl
enabled_cluster_log_types = [
  "api",              # API server
  "audit",            # Who did what
  "authenticator",    # Auth decisions
  "controllerManager",# Controller operations
  "scheduler"         # Pod scheduling
]
```

**Logs go to**: CloudWatch Logs at `/aws/eks/<cluster-name>/cluster`

**Key Insight**: Enable all for production observability!

---

### 💡 Key Patterns Learned Today

1. **API auth mode** - Modern EKS access management
2. **Access Entry + Policy** - Two resources needed for access
3. **SPOT instances** - 70% savings for non-prod
4. **Gitignored tfvars** - Keep secrets out of git
5. **depends_on for IAM** - Attach policies before using roles
6. **Multiple instance types** - Improve SPOT availability
7. **Root user blocked** - Can't add root to access entries
8. **kubeconfig merge** - update-kubeconfig adds, doesn't replace

---

## November 28, 2025 - Dynamic Subnets & Terraform Locals

### 🧮 The `cidrsubnet()` Function

**Problem**: Hardcoded subnet CIDRs don't adapt when VPC CIDR changes.

**Solution**: Use `cidrsubnet()` to calculate dynamically.

```hcl
cidrsubnet(prefix, newbits, netnum)
```

| Parameter | Description | Example |
|-----------|-------------|--------|
| `prefix` | Base CIDR | `"10.0.0.0/16"` |
| `newbits` | Bits to add | `3` (makes /19) |
| `netnum` | Which subnet | `0`, `1`, `2`... |

**Example**:
```hcl
cidrsubnet("10.0.0.0/16", 3, 0) → "10.0.0.0/19"
cidrsubnet("10.0.0.0/16", 3, 1) → "10.0.32.0/19"
cidrsubnet("10.0.0.0/16", 3, 5) → "10.0.160.0/19"
```

**Key Insight**: `netnum` is just "give me subnet #N" - it's an index!

---

### 📦 The `locals` Block

**Problem**: Can't reference one variable from another variable's default.

```hcl
# ❌ This doesn't work!
variable "subnets" {
  default = cidrsubnet(var.vpc_cidr, 3, 0)  # ERROR!
}
```

**Solution**: Use `locals` for computed values.

```hcl
# ✅ This works!
locals {
  subnets = cidrsubnet(var.vpc_cidr, 3, 0)
}
```

**Key Differences**:

| Feature | `variable` | `locals` |
|---------|-----------|----------|
| Set from outside | ✅ Yes | ❌ No |
| Can reference variables | ❌ No (in default) | ✅ Yes |
| Can use functions | ❌ No (in default) | ✅ Yes |
| Access syntax | `var.name` | `local.name` |

**Why `locals` (plural) but `local.` (singular)?**
- `locals` is the **block** that contains multiple values
- `local.xyz` references a **single** value from that block

---

### 🔢 Auto-Calculating Subnet Bits with `log()`

**Challenge**: How many bits to add for N subnets?

**Formula**: `ceil(log(n, 2))`

```hcl
local.new_bits = ceil(log(local.total_subnets, 2))
```

**How it works**:
| Subnets | log₂(n) | ceil() | Bits | Actual Subnets |
|---------|---------|--------|------|----------------|
| 6 | 2.58 | 3 | 3 | 8 (2³) |
| 4 | 2.0 | 2 | 2 | 4 (2²) |
| 9 | 3.17 | 4 | 4 | 16 (2⁴) |

**Why `ceil()`?** Need to round UP to fit all subnets.
- 6 subnets needs 2.58 bits → round up to 3 bits → 8 available slots

---

### 🔄 The `range()` Function

**Problem**: Need to loop N times to create N subnets.

**Solution**: `range(n)` generates list `[0, 1, 2, ..., n-1]`

```hcl
range(6) → [0, 1, 2, 3, 4, 5]

for idx in range(6) : {
  # idx = 0, then 1, then 2... up to 5
}
```

---

### 🎯 Modulo for AZ Distribution

**Problem**: Distribute subnets across 3 AZs evenly.

**Solution**: `idx % length(var.availability_zones)`

```hcl
var.availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

# idx % 3 cycles through 0, 1, 2, 0, 1, 2...
idx=0 → 0%3=0 → us-west-2a
idx=1 → 1%3=1 → us-west-2b
idx=2 → 2%3=2 → us-west-2c
idx=3 → 3%3=0 → us-west-2a  # Wraps around!
idx=4 → 4%3=1 → us-west-2b
idx=5 → 5%3=2 → us-west-2c
```

**Key Insight**: Modulo (%) creates a "circular" pattern!

---

### 🔀 Ternary Conditional for HA Toggle

**Problem**: Different NAT Gateway setup for prod vs dev.

**Solution**: Ternary operator in locals.

```hcl
locals {
  nat_gateway_subnets = var.enable_ha_nat_gateways ? local.public_subnets : {
    "0" = local.public_subnets["0"]
  }
}
```

**Breakdown**:
```
condition ? value_if_true : value_if_false
```

| `enable_ha_nat_gateways` | Result |
|--------------------------|--------|
| `true` | All 3 public subnets → 3 NAT Gateways |
| `false` | Only first subnet → 1 NAT Gateway |

---

### 📝 Module Documentation Best Practices

**Created comprehensive README for VPC module**:

1. **Features list** with emoji highlights
2. **ASCII architecture diagram**
3. **Usage examples** (basic, advanced, cost-optimized)
4. **Input/Output tables** with types and defaults
5. **How it works** section explaining the math
6. **Cost estimation** table
7. **Links to related docs**

**Why it matters**:
- Reduces "how do I use this?" questions
- Documents the "why" not just the "what"

---

### 💡 Key Patterns Learned Today

1. **`locals` for computed values** - When variables can't reference each other
2. **`cidrsubnet()` for dynamic CIDRs** - Never hardcode subnets again
3. **`ceil(log(n, 2))`** - Auto-calculate subnet bits
4. **`range(n)`** - Loop N times
5. **`idx % len`** - Distribute evenly across a list
6. **Ternary in locals** - Toggle behavior with boolean
7. **Module README** - Professional documentation

---

## November 27, 2025 - NAT Gateway & Advanced For Loops

### 🌐 NAT Gateway Architecture

**Problem**: Private subnets need internet access but shouldn't be directly exposed.

**Solution**: NAT Gateway in public subnet + private route table

**How it works**:
1. Private subnet → NAT Gateway (in public subnet)
2. NAT Gateway → Internet Gateway
3. Return traffic follows same path in reverse

**Key Insight**:
- NAT Gateway **must** be in public subnet (needs public IP)
- Private route table points `0.0.0.0/0` to NAT Gateway ID
- NAT Gateway handles IP address translation (private → public)

**High Availability Pattern**:
```
AZ-A: Private Subnet A → NAT Gateway A (in Public Subnet A) → IGW
AZ-B: Private Subnet B → NAT Gateway B (in Public Subnet B) → IGW
AZ-C: Private Subnet C → NAT Gateway C (in Public Subnet C) → IGW
```

**Why not share one NAT?**: Single NAT = single point of failure for all private subnets

---

### 🔄 Advanced For Loop with Nested Filtering

**Challenge**: Match each private subnet with NAT Gateway in the **same** availability zone.

**Problem Details**:
- Public subnets have keys: `"0"`, `"1"`, `"2"` (indices 0-2)
- Private subnets have keys: `"3"`, `"4"`, `"5"` (indices 3-5)
- NAT Gateways created from public subnets (keys `"0"`, `"1"`, `"2"`)
- Need to match: Private subnet in `us-west-2a` → NAT in `us-west-2a`

**Failed Approach #1**: Direct key matching
```hcl
# ❌ Doesn't work - keys don't match ("3" vs "0")
nat_gateway_id = aws_nat_gateway.eks_nat_gateway[each.key].id
```

**Failed Approach #2**: Simple index arithmetic
```hcl
# ❌ Too fragile - breaks if subnet order changes
nat_gateway_id = aws_nat_gateway.eks_nat_gateway[tostring(tonumber(each.key) - 3)].id
```

**Successful Approach**: AZ-based matching with for loop ✅
```hcl
nat_gateway_id = [
  for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
  if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
][0]
```

**How it works**:
1. `for k, nat in aws_nat_gateway.eks_nat_gateway` - Loop through all 3 NAT Gateways
2. `: nat.id` - Extract NAT Gateway ID
3. `if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone` - Filter by AZ match
4. `[0]` - Extract first (and only) matching NAT Gateway ID from list

**Key Learning**: When keys don't align, **match by properties** (AZ) not by keys!

---

### 📊 The `[0]` Extraction Pattern

**Problem**: Terraform route expects a **single** NAT Gateway ID (scalar), but `for` loop returns a **list**.

```hcl
# This creates a list with 1 element
result = [for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id if <condition>]
# result type: list(string)

# Route table needs a scalar
nat_gateway_id = "nat-123abc"  # ✅ scalar string
nat_gateway_id = ["nat-123abc"] # ❌ list of strings
```

**Solution**: Use `[0]` to extract first element
```hcl
nat_gateway_id = [...filter logic...][0]  # Converts list to scalar
```

**When to use**:
- ✅ When you **know** filter returns exactly 1 item (like our AZ match)
- ✅ When resource attribute expects scalar, not list
- ❌ Don't use if filter might return 0 or multiple items (will error)

**Safety**: Our case is safe because:
- Each AZ has exactly 1 NAT Gateway
- Each private subnet is in exactly 1 AZ
- Therefore: Filter always returns exactly 1 match

---

### 🏷️ Tag Merging with `merge()` Function

**Problem**: Want common tags on all resources + resource-specific tags.

**Old approach** (verbose):
```hcl
tags = {
  ManagedBy   = "Terraform"
  Project     = "production-eks-platform"
  Environment = var.environment
  Name        = "eks-vpc"
}

# Repeat for every resource... 😓
```

**Better approach** with `merge()`:
```hcl
# Define common tags once
variable "resource_tag" {
  default = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}

# Merge with resource-specific tags
resource "aws_vpc" "eks_vpc" {
  tags = merge(var.resource_tag, {
    Name        = "${var.environment}-eks-vpc"
    Environment = var.environment
  })
}
```

**How `merge()` works**:
```hcl
merge({a = 1, b = 2}, {b = 3, c = 4})
# Result: {a = 1, b = 3, c = 4}
# Later values override earlier ones
```

**Benefits**:
- ✅ DRY - Define common tags once
- ✅ Consistency - All resources get same base tags
- ✅ Flexibility - Easy to add resource-specific tags
- ✅ Maintainability - Update common tags in one place

**Pattern for all resources**:
```hcl
tags = merge(var.resource_tag, {
  Name = "<resource-specific-name>"
  # Any other specific tags
})
```

---

### 🎯 Kubernetes Subnet Tagging

**Learned**: EKS uses specific tags to discover subnets for load balancers.

**Required tags**:
```hcl
# Public subnets (for internet-facing load balancers)
"kubernetes.io/role/elb" = "1"

# Private subnets (for internal load balancers)
"kubernetes.io/role/internal-elb" = "1"

# Both types (for cluster association)
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"
```

**Why it matters**:
- EKS automatically provisions ELBs when you create LoadBalancer services
- Without these tags, EKS doesn't know which subnets to use
- `shared` value means subnet can be used by multiple clusters

**Alternative values**:
- `owned` - Subnet dedicated to single cluster only
- `shared` - Subnet shared across multiple clusters (our choice)

---

### 💰 Cost Awareness

**Learned**: Infrastructure decisions have real $ impact

**NAT Gateway costs**:
- Base: $0.045/hour ≈ $32.40/month **per NAT Gateway**
- Data processing: $0.045/GB transferred
- Our setup: 3 NAT × $32.40 = **$97.20/month** (before data transfer)

**Trade-off decision**:
- 1 NAT Gateway: ~$32/month, single point of failure ❌
- 3 NAT Gateways: ~$97/month, high availability ✅
- **Decision**: Production workload justifies HA cost

**Key Insight**: Always document cost implications in ADRs for future reference.

---

### 🔧 Terraform Best Practices Applied

**Snake_case naming**:
```hcl
# ❌ Old (hyphens)
resource "aws_vpc" "eks-vpc" {}

# ✅ New (snake_case)
resource "aws_vpc" "eks_vpc" {}
```
**Why**: Terraform best practice, easier to reference in code.

**Dynamic resource naming**:
```hcl
# ✅ Includes environment and AZ
Name = "${var.environment}-eks-public-subnet-${each.value.availability_zone}"
# Result: "dev-eks-public-subnet-us-west-2a"
```
**Why**: Clear identification in AWS console, avoids naming conflicts.

**Conditional resource creation**:
```hcl
# Public route tables - only for subnets with map_public_ip_on_launch = true
for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet if subnet.map_public_ip_on_launch }

# Private route tables - only for subnets with map_public_ip_on_launch = false  
for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet if !subnet.map_public_ip_on_launch }
```
**Why**: Single source of truth, no hardcoded subnet indices.

---

## November 26, 2025 - VPC & Terraform Fundamentals

### 🧠 Subnet CIDR Calculation

**Problem**: How to divide `10.0.0.0/16` VPC into 6 subnets?

**Learning**: 
- Need to round up to next power of 2 (6 → 8 subnets)
- Calculate required bits: 2^3 = 8, so need 3 additional bits
- `/16 + 3 = /19` subnet mask
- Each `/19` provides 8,192 IPs (2^13)
- Third octet increments by 32 (256 ÷ 8)

**Formula**:
```
Number of subnets needed → Round to power of 2 → Calculate bits → Add to original CIDR
6 subnets → 8 (2^3) → 3 bits → /16 + 3 = /19
```

**Result**: 
- `10.0.0.0/19`, `10.0.32.0/19`, `10.0.64.0/19`, etc.
- Pattern: Add 32 to third octet each time

---

### 🔧 Terraform `for_each` with Lists vs Maps

**Problem**: `for_each` expects map keys to be strings, but list indices are numbers.

**Solution**:
```hcl
# Converting list to map with string keys
for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet }
```

**Key Insight**:
- When source is a **list**: `idx` is a number → need `tostring(idx)`
- When source is a **map**: keys are already strings → no conversion needed

**Example**:
```hcl
# First resource creates map from list
resource "aws_subnet" "subnets" {
  for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet }
  # Creates map: {"0" => {...}, "1" => {...}}
}

# Second resource uses that map
resource "aws_route_table_association" "assoc" {
  for_each = { for k, v in aws_subnet.subnets : k => v if v.map_public_ip_on_launch }
  # k is already a string ("0", "1", "2"), no conversion needed
}
```

---

### 🛣️ Route Tables Deep Dive

**What I thought**: Route table CIDR should match subnet CIDR (e.g., `10.0.1.0/24`)

**What I learned**:
- Route table defines **destination-based routing rules**
- `0.0.0.0/0` means "all internet traffic" (default route)
- Format: `cidr_block` = destination, `gateway_id` = next hop

**Common Patterns**:
- Public subnets: `0.0.0.0/0` → Internet Gateway
- Private subnets: `0.0.0.0/0` → NAT Gateway
- VPC peering: `10.1.0.0/16` → Peering Connection
- Local traffic: Handled automatically within VPC

**Analogy**: Route table is like GPS directions - "For traffic going to X, send it through Y"

---

### 🎯 Conditional Resource Creation

**Challenge**: Only attach route table to public subnets (where `map_public_ip_on_launch = true`)

**Solution**: Filter in `for_each` comprehension
```hcl
for_each = { for k, v in aws_subnet.subnets : k => v if v.map_public_ip_on_launch }
```

**Breakdown**:
1. Loop through all subnets (`for k, v in aws_subnet.subnets`)
2. Recreate key-value pairs (`k => v`)
3. Apply filter condition (`if v.map_public_ip_on_launch`)

**Result**: Only creates associations for subnets where condition is true (3 public subnets)

---

### 📁 List vs Map Variables - When to Use What?

**Question**: Should `vpc_subnets` be a list or map?

**Answer**: Depends on use case

**Use List when**:
- Items are sequential/ordered ✅ (our case)
- Simple iteration needed
- Easy to read and maintain
- No need for named references

**Use Map when**:
- Need to reference by name (`var.vpc_subnets["public-1"]`)
- Conditional override of specific items
- Individual management in other modules

**Decision**: Kept list for simplicity and natural ordering of 6 subnets

---

### 🔒 Git Security Best Practices

**Created comprehensive `.gitignore` for Terraform**:

**Critical items to exclude**:
- `.terraform/` - Contains provider binaries and cached modules
- `*.tfstate` - Contains sensitive infrastructure data (passwords, IPs, ARNs)
- `*.tfvars` - Often contains secrets, API keys, credentials
- `*.pem`, `*.key` - Private keys for SSH/SSL
- `.env` files - Environment variables with secrets

**Why it matters**:
- State files can expose infrastructure details to attackers
- Credentials in version control = security breach
- Provider binaries are large and environment-specific

---

### 💡 Module Design Philosophy

**Learned**: Balance between flexibility and simplicity

**Good module design**:
- ✅ Parameterized with variables (VPC CIDR, subnets)
- ✅ Reusable across environments (dev/staging/prod)
- ✅ Sensible defaults for common use cases
- ✅ Clear naming and documentation

**Our VPC module**:
```hcl
module "vpc" {
  source      = "../../modules/vpc"
  environment = "dev"
  # Other variables have defaults, making it simple to use
}
```

---

### 🎓 Key Terraform Patterns Learned

1. **Dynamic resource creation**: `for_each` over lists/maps
2. **Type conversion**: `tostring()`, `tonumber()`, `tobool()`
3. **Conditional logic**: `if` in comprehensions
4. **List comprehension**: `{ for k, v in collection : key => value }`
5. **Resource dependencies**: Terraform handles automatically via references

