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