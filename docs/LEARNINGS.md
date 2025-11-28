# Learning Journal

This document tracks key learnings, insights, and "aha moments" throughout the project.

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