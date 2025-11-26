# Troubleshooting Guide

Common issues encountered during development and their solutions.

---
 
## Terraform Issues

### Issue: `for_each` Error - "The key must be a string"

**Error Message**:
```
Error: Invalid for_each argument
The given "for_each" argument value is unsuitable: the "for_each" map includes keys derived from resource attributes that cannot be determined until apply
```

**Cause**: Using numeric index directly as `for_each` key.

**Solution**:
```hcl
# ❌ Wrong
for_each = { for idx, subnet in var.vpc_subnets : idx => subnet }

# ✅ Correct
for_each = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet }
```

**Explanation**: `for_each` requires string keys, but list indices are numbers. Use `tostring()` to convert.

---

### Issue: Route Table Association Missing `for_each`

**Error Message**:
```
Error: Reference to undeclared resource
A managed resource "aws_route_table_association" "eks-route-table-assoc" has not been declared in the root module.
```

**Cause**: Using `each.key` without defining `for_each`.

**Solution**:
```hcl
# ❌ Wrong
resource "aws_route_table_association" "eks-route-table-assoc" {
  subnet_id      = aws_subnet.subnets[each.key].id  # each.key without for_each!
  route_table_id = aws_route_table.eks-route-table.id
}

# ✅ Correct
resource "aws_route_table_association" "eks-route-table-assoc" {
  for_each       = aws_subnet.subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.eks-route-table.id
}
```

---

### Issue: Wrong CIDR in Route Table

**Symptom**: Internet connectivity not working from public subnets.

**Mistake**:
```hcl
# ❌ Wrong - This routes only one specific subnet
resource "aws_route_table" "public" {
  route {
    cidr_block = "10.0.1.0/24"  # Specific subnet CIDR
    gateway_id = aws_internet_gateway.gw.id
  }
}
```

**Solution**:
```hcl
# ✅ Correct - Route all internet traffic
resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"  # All internet destinations
    gateway_id = aws_internet_gateway.gw.id
  }
}
```

**Explanation**: `0.0.0.0/0` is the default route for all internet traffic. Using a specific CIDR only routes traffic to that destination.

---

### Issue: Terraform State Lock

**Error Message**:
```
Error: Error acquiring the state lock
Lock Info:
  ID:        abc123...
  Path:      aws-eks-clusters-terraform-state/dev/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
  Version:   1.5.0
  Created:   2025-11-26 10:30:00
```

**Cause**: Previous Terraform operation didn't complete cleanly, or another user is running Terraform.

**Solutions**:

1. **Wait**: If someone else is running Terraform, wait for them to finish.

2. **Force unlock** (if you're sure no one else is running it):
```bash
terraform force-unlock <LOCK_ID>
# Example: terraform force-unlock abc123...
```

3. **Prevention**: Always let Terraform complete or use `Ctrl+C` gracefully.

---

### Issue: AWS Provider Region Mismatch

**Symptom**: Resources created in wrong region.

**Check**:
```hcl
provider "aws" {
  region  = "us-west-2"  # Make sure this matches your intent
  profile = "default"
}
```

**Also verify**: AWS CLI default region
```bash
aws configure get region
```

---

## AWS Issues

### Issue: VPC CIDR Already in Use

**Error Message**:
```
Error: error creating VPC: VpcLimitExceeded: The maximum number of VPCs has been reached
```

**Solutions**:

1. **Check current VPCs**:
```bash
aws ec2 describe-vpcs --region us-west-2
```

2. **Delete unused VPCs**:
```bash
# First, delete dependencies (subnets, IGW, etc.)
# Then delete VPC
aws ec2 delete-vpc --vpc-id vpc-xxxxxx
```

3. **Request limit increase**: AWS Support Console → Service Quotas

---

### Issue: Subnet CIDR Conflicts

**Error Message**:
```
Error: error creating subnet: InvalidSubnet.Conflict: The CIDR '10.0.0.0/19' conflicts with another subnet
```

**Cause**: Overlapping CIDR blocks.

**Solution**: Verify subnets don't overlap
```
✅ Correct (non-overlapping):
10.0.0.0/19   → 10.0.0.0   - 10.0.31.255
10.0.32.0/19  → 10.0.32.0  - 10.0.63.255

❌ Wrong (overlapping):
10.0.0.0/19   → 10.0.0.0   - 10.0.31.255
10.0.16.0/20  → 10.0.16.0  - 10.0.31.255  (overlaps!)
```

---

## Git Issues

### Issue: Accidentally Committed `.tfstate` File

**Symptom**: State file visible in git history (security risk!).

**Immediate Action**:
```bash
# Remove from staging
git reset HEAD terraform.tfstate

# Remove from git history (if already committed)
git filter-branch --index-filter 'git rm --cached --ignore-unmatch terraform.tfstate' HEAD

# Force push (⚠️ only if working alone)
git push --force
```

**Prevention**: Ensure `.gitignore` includes:
```
*.tfstate
*.tfstate.*
```

---

### Issue: Large `.terraform/` Directory in Git

**Symptom**: Git repo size bloated with provider binaries.

**Solution**:
```bash
# Add to .gitignore
echo ".terraform/" >> .gitignore

# Remove from git
git rm -r --cached .terraform/
git commit -m "chore: remove .terraform directory from git"
```

---

## Module Issues

### Issue: Module Not Found

**Error Message**:
```
Error: Module not installed
This module is not yet installed. Run "terraform init" to install all modules required by this configuration.
```

**Solution**:
```bash
cd terraform/environments/dev
terraform init
```

---

### Issue: Module Variable Not Passed

**Symptom**: Module uses default value instead of provided value.

**Check**:
```hcl
# ❌ Wrong - typo in variable name
module "vpc" {
  source = "../../modules/vpc"
  
  enviornment = "dev"  # Typo! Should be "environment"
}

# ✅ Correct
module "vpc" {
  source = "../../modules/vpc"
  
  environment = "dev"
}
```

**Debug**:
```bash
terraform plan  # Will show which variables are being used
```

---

## Networking Issues

### Issue: Can't SSH to EC2 in Public Subnet

**Checklist**:
1. ✅ Instance has public IP?
2. ✅ Internet Gateway attached to VPC?
3. ✅ Route table has `0.0.0.0/0` → IGW?
4. ✅ Route table associated with subnet?
5. ✅ Security group allows port 22 from your IP?
6. ✅ NACL allows inbound/outbound traffic?
7. ✅ Correct SSH key pair?

**Verify route table**:
```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxx"
```

---

## Performance Issues

### Issue: Terraform Plan/Apply Very Slow

**Causes & Solutions**:

1. **Too many resources**: Use `-target` for specific resources
```bash
terraform plan -target=module.vpc
```

2. **Large state file**: Consider splitting into multiple state files

3. **Network latency**: Use VPN or faster internet connection

4. **Provider version**: Update to latest version
```bash
terraform init -upgrade
```

---

## Common Mistakes (Lessons Learned)

### ❌ Hardcoding Values
```hcl
# Bad
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"  # Hardcoded
}
```

### ✅ Use Variables
```hcl
# Good
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}
```

---

### ❌ Not Tagging Resources
```hcl
# Bad - no tags
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}
```

### ✅ Always Tag
```hcl
# Good
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
  
  tags = {
    Name        = "eks-vpc-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

---

## Quick Reference Commands

### Terraform
```bash
# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Show current state
terraform show

# List resources in state
terraform state list

# Show specific resource
terraform state show aws_vpc.main

# Refresh state
terraform refresh

# Destroy specific resource
terraform destroy -target=aws_instance.example
```

### AWS CLI
```bash
# List VPCs
aws ec2 describe-vpcs

# List subnets in VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx"

# List route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxx"

# Verify internet gateway
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-xxxxx"
```

---

## Getting Help

### Resources
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [Terraform Community Forum](https://discuss.hashicorp.com/)
- [AWS re:Post](https://repost.aws/)

### Before Asking for Help
1. ✅ Read the error message completely
2. ✅ Run `terraform validate`
3. ✅ Check `terraform plan` output
4. ✅ Verify AWS credentials
5. ✅ Search error message on Google/StackOverflow
6. ✅ Check this troubleshooting guide

---
