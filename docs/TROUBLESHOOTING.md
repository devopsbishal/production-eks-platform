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

## Locals & Dynamic Subnet Issues

### Issue: `locals.` vs `local.` Confusion

**Error Message**:
```
Error: Reference to undeclared local value
A local value with the name "vpc_subnets" has not been declared.
```

**Cause**: Using `locals.vpc_subnets` instead of `local.vpc_subnets`.

**Solution**:
```hcl
# ❌ Wrong - "locals" with 's'
availability_zone = locals.availability_zones[idx % 3]

# ✅ Correct - "local" without 's'
availability_zone = local.availability_zones[idx % 3]
```

**Remember**:
- `locals { }` - Block definition (plural)
- `local.xyz` - Reference (singular)

---

### Issue: Variable Can't Reference Another Variable

**Error Message**:
```
Error: Variables not allowed
Variables may not be used here.
```

**Cause**: Trying to use `var.x` inside another variable's default.

```hcl
# ❌ This doesn't work!
variable "subnets" {
  default = cidrsubnet(var.vpc_cidr_block, 3, 0)
}
```

**Solution**: Use `locals` instead.

```hcl
# ✅ This works!
locals {
  subnets = cidrsubnet(var.vpc_cidr_block, 3, 0)
}
```

**Explanation**: Variables are evaluated before expressions. Use `locals` for computed values.

---

### Issue: `for_each` with Ternary Returns Wrong Type

**Error Message**:
```
Error: Invalid for_each argument
The given "for_each" argument value is unsuitable: the "for_each" argument must be a map, or set of strings
```

**Cause**: Ternary returning different types (map vs single object).

```hcl
# ❌ Wrong - [0] returns an object, not a map
for_each = var.enable_ha ? local.public_subnets : local.public_subnets[0]
```

**Solution**: Both branches must return maps.

```hcl
# ✅ Correct - both return maps
for_each = var.enable_ha ? local.public_subnets : {
  "0" = local.public_subnets["0"]
}
```

---

### Issue: `cidrsubnet()` Invalid Prefix

**Error Message**:
```
Error: Error in function call
Call to function "cidrsubnet" failed: invalid CIDR address: "10.0.0.0"
```

**Cause**: Missing CIDR notation (needs `/16`, `/24`, etc.).

```hcl
# ❌ Wrong - no CIDR notation
cidrsubnet("10.0.0.0", 3, 0)

# ✅ Correct - includes /16
cidrsubnet("10.0.0.0/16", 3, 0)
```

---

### Issue: Too Many Subnets for CIDR

**Error Message**:
```
Error: Error in function call
Call to function "cidrsubnet" failed: prefix extension of 3 bits would result in a prefix of 27 bits, which is longer than the maximum of 24 bits for IPv4 addresses.
```

**Cause**: Trying to create more subnets than the CIDR can support.

**Example**:
- VPC: `/24` (256 IPs)
- Trying to add 3 bits: `/24 + 3 = /27`
- But `/27` only gives 32 IPs per subnet

**Solution**: Use a larger VPC CIDR or fewer subnets.

```hcl
# Use /16 for flexibility (65,536 IPs)
vpc_cidr_block = "10.0.0.0/16"
```

---

### Issue: NAT Gateway Routing Mismatch After HA Toggle

**Symptom**: Private subnets can't reach internet after changing `enable_ha_nat_gateways`.

**Cause**: Route table still pointing to non-existent NAT Gateway.

**Solution**:
```bash
# Destroy and recreate to reset routing
terraform destroy -target=module.vpc
terraform apply
```

**Prevention**: The code handles this with conditional routing:
```hcl
nat_gateway_id = var.enable_ha_nat_gateways ? [
  for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
  if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
][0] : aws_nat_gateway.eks_nat_gateway["0"].id
```

---

## EKS Issues

### Issue: "Your current IAM principal doesn't have access to Kubernetes objects"

**Error in AWS Console**:
```
Your current IAM principal doesn't have access to Kubernetes objects on this cluster.
This might be due to the current principal not having an IAM access entry with permissions to access the cluster.
```

**Cause**: Using API authentication mode without an access entry for your IAM principal.

**Solution**:
```hcl
# Add access entry in Terraform
access_entries = {
  my_user = {
    principal_arn = "arn:aws:iam::ACCOUNT_ID:user/MY_USER"
  }
}
```

Or via CLI:
```bash
# Create access entry
aws eks create-access-entry \
  --cluster-name eks-cluster-dev \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/MY_USER

# Associate admin policy
aws eks associate-access-policy \
  --cluster-name eks-cluster-dev \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/MY_USER \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

---

### Issue: Cannot Add Root User to Access Entries

**Error Message**:
```
ValidationException: Root user cannot be used as principal
```

**Cause**: AWS explicitly blocks root user from EKS access entries (security best practice).

**Solutions**:
1. **Create dedicated IAM user** for console access
2. **Use IAM role** (SSO, federated identity)
3. **Enable console password** for existing CLI user

---

### Issue: kubectl Unauthorized After Cluster Creation

**Error Message**:
```
error: You must be logged in to the server (Unauthorized)
```

**Causes & Solutions**:

1. **Kubeconfig not updated**:
```bash
aws eks update-kubeconfig --region us-west-2 --name eks-cluster-dev
```

2. **Wrong IAM identity**:
```bash
# Check current identity
aws sts get-caller-identity

# Must match principal_arn in access_entries
```

3. **No access entry exists**:
```bash
# List access entries
aws eks list-access-entries --cluster-name eks-cluster-dev
```

---

### Issue: Nodes Not Joining Cluster

**Symptom**: `kubectl get nodes` shows no nodes or nodes in `NotReady` state.

**Checklist**:
1. ✅ Nodes in private subnets with NAT Gateway?
2. ✅ Node group IAM role has required policies?
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
3. ✅ Subnets have Kubernetes tags?
   - `kubernetes.io/cluster/<cluster-name> = shared`
4. ✅ Security groups allow node-to-control-plane traffic?

**Debug**:
```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name eks-cluster-dev \
  --nodegroup-name eks-cluster-dev-node-group

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=eks-cluster-dev"
```

---

### Issue: EKS Cluster Creation Timeout

**Symptom**: Terraform hangs for 20+ minutes then times out.

**Cause**: EKS cluster creation takes 10-15 minutes normally.

**Solutions**:
1. **Be patient**: First creation takes ~15 minutes
2. **Check AWS Console**: See actual cluster status
3. **Increase timeout** (if needed):
```hcl
resource "aws_eks_cluster" "eks_cluster" {
  # ...
  timeouts {
    create = "30m"
    delete = "15m"
  }
}
```

---

### Issue: SPOT Instance Capacity Errors

**Error Message**:
```
InsufficientInstanceCapacity: There is no Spot capacity available that matches your request.
```

**Solutions**:
1. **Use multiple instance types**:
```hcl
node_group_instance_types = ["t3.medium", "t3.large", "t3a.medium"]
```

2. **Switch to ON_DEMAND temporarily**:
```hcl
node_group_capacity_type = "ON_DEMAND"
```

3. **Try different AZs**: Some AZs have more SPOT capacity

---

### Issue: Access Entry Policy Association Failed

**Error Message**:
```
ResourceNotFoundException: The access entry for principal ... does not exist
```

**Cause**: Trying to associate policy before access entry is created.

**Solution**: Ensure `depends_on` is set:
```hcl
resource "aws_eks_access_policy_association" "assoc" {
  # ...
  depends_on = [aws_eks_access_entry.access_entries]
}
```

---

### Issue: Wrong kubeconfig Context

**Symptom**: kubectl commands affect wrong cluster.

**Check current context**:
```bash
kubectl config current-context
```

**List all contexts**:
```bash
kubectl config get-contexts
```

**Switch context**:
```bash
kubectl config use-context arn:aws:eks:us-west-2:ACCOUNT:cluster/eks-cluster-dev
```

---

## Getting Help

### Resources
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Terraform Community Forum](https://discuss.hashicorp.com/)
- [AWS re:Post](https://repost.aws/)

### Before Asking for Help
1. ✅ Read the error message completely
2. ✅ Run `terraform validate`
3. ✅ Check `terraform plan` output
4. ✅ Verify AWS credentials (`aws sts get-caller-identity`)
5. ✅ Check EKS cluster status in AWS Console
6. ✅ Search error message on Google/StackOverflow
7. ✅ Check this troubleshooting guide

---
