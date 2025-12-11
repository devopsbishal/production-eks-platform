# Troubleshooting Guide

Common issues encountered during development and their solutions.

---

## External DNS Issues

### Issue: DNS Record Not Created

**Symptom**: Applied Ingress with External DNS annotation but no Route53 record appears.

**Diagnosis**:
```bash
# Check External DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns

# Check if External DNS pod is running
kubectl get pods -n kube-system | grep external-dns
```

**Common Causes & Solutions**:

1. **Domain filter mismatch**:
   ```bash
   # Ingress annotation
   external-dns.alpha.kubernetes.io/hostname: app.wrong-domain.com
   
   # But External DNS is configured for
   domainFilters: eks.rentalhubnepal.com
   ```
   **Fix**: Ensure hostname matches configured domain filter.

2. **IRSA not working**:
   ```bash
   # Check ServiceAccount annotation
   kubectl get sa external-dns -n kube-system -o yaml | grep eks.amazonaws.com
   ```
   **Fix**: Verify IRSA role ARN annotation exists.

3. **IAM permissions missing**:
   ```
   Error: AccessDenied: User is not authorized to perform: route53:ChangeResourceRecordSets
   ```
   **Fix**: Check IAM policy attached to External DNS role.

4. **Wrong hosted zone**:
   ```bash
   # List zones External DNS can see
   aws route53 list-hosted-zones
   ```
   **Fix**: Ensure Route53 zone exists for the domain.

---

### Issue: Subdomain Delegation Not Working

**Symptom**: `dig app.eks.example.com` returns `NXDOMAIN` or times out.

**Diagnosis**:
```bash
# Check NS delegation
dig NS eks.example.com +short

# Should return Route53 name servers like:
# ns-123.awsdns-45.com
# ns-678.awsdns-12.net
```

**Causes & Solutions**:

1. **NS records not added in Cloudflare**:
   ```bash
   # Get Route53 name servers
   terraform output route53_name_servers
   ```
   **Fix**: Add 4 NS records in Cloudflare for the subdomain.

2. **Wrong NS record name**:
   - ❌ Name: `eks.example.com`
   - ✅ Name: `eks` (just the subdomain prefix)

3. **DNS propagation delay**:
   **Fix**: Wait 5-10 minutes, DNS changes take time to propagate.

4. **Cloudflare proxy enabled**:
   NS records cannot be proxied (orange cloud).
   **Fix**: Ensure NS records show grey cloud (DNS only).

---

### Issue: External DNS Creates Wrong Record Type

**Symptom**: Creates CNAME instead of A record, or wrong IP.

**Cause**: ALB Controller uses hostname-based targets.

**Solution**: External DNS creates alias/CNAME for ALB hostnames. This is correct behavior.

For true A records, use `external-dns.alpha.kubernetes.io/target` annotation:
```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: app.eks.example.com
  external-dns.alpha.kubernetes.io/target: 1.2.3.4
```

---

### Issue: TXT Record Conflicts

**Error**: `TXT record already exists with different owner`

**Cause**: Another External DNS instance (different cluster) created the record.

**Solution**: 
1. Use unique `txtOwnerId` per cluster
2. Delete orphaned TXT records manually in Route53
3. Consider `policy: upsert-only` to prevent deletions

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

## Availability Zone Issues

### Issue: Invalid Availability Zones Provided

**Error Message**:
```
Error: Invalid function argument
cannot convert "ERROR: Invalid availability zones provided: us-east-1a, us-east-1b.
Available AZs: us-west-2a, us-west-2b, us-west-2c, us-west-2d" to bool
```

**Cause**: You provided AZs that don't exist in the current region.

**Solution**:
1. **Remove the override** - Let module auto-fetch AZs:
```hcl
module "vpc" {
  source = "../../modules/vpc"
  # Don't set availability_zones - it will auto-fetch
}
```

2. **Use correct AZs** for your region:
```hcl
# For us-west-2
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

# For us-east-1
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

**Check available AZs**:
```bash
aws ec2 describe-availability-zones --region us-west-2 --query 'AvailabilityZones[].ZoneName'
```

---

### Issue: Requesting More AZs Than Available

**Symptom**: Module uses fewer AZs than expected.

**Cause**: `az_count` exceeds available AZs in region.

**Example**:
- Set `az_count = 5`
- Region only has 4 AZs
- Module uses 4 AZs (capped by `min()`)

**Solution**: This is actually safe behavior! The module caps at available AZs.

To verify available AZs:
```bash
aws ec2 describe-availability-zones --region us-west-2 | jq '.AvailabilityZones | length'
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

## EBS CSI Driver Issues

### Issue: PVC Stuck in Pending State

**Symptom**: PersistentVolumeClaim remains in `Pending` status, pod can't start.

**Diagnosis**:
```bash
# Check PVC status
kubectl get pvc

# Describe PVC for events
kubectl describe pvc <pvc-name>

# Check CSI driver pods
kubectl get pods -n kube-system | grep ebs-csi
```

**Common Causes & Solutions**:

1. **EBS CSI Driver not installed**
   ```bash
   # Check if CSI driver deployed
   kubectl get deployment -n kube-system ebs-csi-controller
   kubectl get daemonset -n kube-system ebs-csi-node
   ```
   **Fix**: Install EBS CSI Driver via Terraform.

2. **StorageClass doesn't exist**
   ```bash
   kubectl get storageclass
   ```
   **Fix**: Create StorageClass:
   ```yaml
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: ebs-gp3
   provisioner: ebs.csi.aws.com
   parameters:
     type: gp3
   ```

3. **IAM permissions missing**
   ```bash
   # Check CSI driver logs
   kubectl logs -n kube-system -l app=ebs-csi-controller
   ```
   Error: `AccessDenied: User is not authorized to perform: ec2:CreateVolume`
   
   **Fix**: Attach `AmazonEBSCSIDriverPolicy` to IAM role.

4. **Pod Identity agent not running**
   ```bash
   # Check pod identity agent
   kubectl get daemonset -n kube-system eks-pod-identity-agent
   ```
   **Fix**: Install `eks-pod-identity-agent` addon first.

---

### Issue: Volume Fails to Attach to Node

**Error in pod events**:
```
AttachVolume.Attach failed for volume "pvc-xxx": attachment of disk "vol-xxx" failed, expected device /dev/xvdba but found /dev/xvdbb
```

**Causes & Solutions**:

1. **Too many volumes on node**
   - EKS nodes have volume attachment limits (varies by instance type)
   - t3.medium: ~12 volumes max
   
   **Check**:
   ```bash
   # List volumes attached to instance
   aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=<instance-id>"
   ```
   
   **Fix**: Scale node group or use larger instance types.

2. **Volume in different AZ than node**
   ```bash
   # Check volume AZ
   aws ec2 describe-volumes --volume-ids vol-xxx --query "Volumes[0].AvailabilityZone"
   
   # Check node AZ
   kubectl get node <node-name> -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'
   ```
   
   **Fix**: EBS volumes are AZ-specific. CSI driver should handle this, but if it fails:
   - Delete PVC and recreate
   - Ensure nodes exist in all AZs

3. **Volume already attached elsewhere**
   ```bash
   aws ec2 describe-volumes --volume-ids vol-xxx --query "Volumes[0].Attachments"
   ```
   
   **Fix**: Manually detach volume or delete stale pod.

---

### Issue: Pod Identity Association Not Working

**Error in CSI driver logs**:
```
NoCredentialProviders: no valid providers in chain
```

**Diagnosis**:
```bash
# Check Pod Identity association
aws eks list-pod-identity-associations --cluster-name <cluster-name>

# Describe specific association
aws eks describe-pod-identity-association \
  --cluster-name <cluster-name> \
  --association-id <assoc-id>

# Check from pod
kubectl exec -it -n kube-system <ebs-csi-controller-pod> -- aws sts get-caller-identity
```

**Common Causes**:

1. **eks-pod-identity-agent not installed**
   ```bash
   kubectl get daemonset -n kube-system eks-pod-identity-agent
   ```
   **Fix**: Install addon:
   ```hcl
   resource "aws_eks_addon" "pod_identity_agent" {
     cluster_name  = var.cluster_name
     addon_name    = "eks-pod-identity-agent"
     addon_version = "v1.0.0-eksbuild.1"
   }
   ```

2. **ServiceAccount name mismatch**
   ```bash
   # Check association
   aws eks describe-pod-identity-association ... --query "association.serviceAccount"
   
   # Check what CSI driver uses
   kubectl get deployment -n kube-system ebs-csi-controller -o jsonpath='{.spec.template.spec.serviceAccountName}'
   ```
   **Fix**: Ensure names match exactly (typically `ebs-csi-controller-sa`).

3. **IAM role trust policy wrong**
   ```bash
   aws iam get-role --role-name <role-name> --query "Role.AssumeRolePolicyDocument"
   ```
   
   Should trust `pods.eks.amazonaws.com`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "Service": "pods.eks.amazonaws.com"
       },
       "Action": ["sts:AssumeRole", "sts:TagSession"]
     }]
   }
   ```

4. **Namespace mismatch**
   - Association must specify `namespace: kube-system`
   - CSI driver must be in same namespace

---

### Issue: Volume Not Deleted After PVC Deletion

**Symptom**: Deleted PVC but EBS volume still exists (incurring costs).

**Check**:
```bash
# List volumes
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=<pvc-name>"
```

**Cause**: `reclaimPolicy: Retain` in StorageClass.

**Solution**:
```yaml
# Set to Delete for automatic cleanup
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete  # ✅ Auto-delete when PVC deleted
parameters:
  type: gp3
```

**Manual cleanup**:
```bash
# Delete orphaned volume
aws ec2 delete-volume --volume-id vol-xxx
```

---

### Issue: Dynamic Provisioning Not Working

**Symptom**: Created PVC but no volume created.

**Check events**:
```bash
kubectl describe pvc <pvc-name>
```

**Common Causes**:

1. **No default StorageClass**
   ```bash
   kubectl get storageclass
   # Look for "(default)" annotation
   ```
   
   **Fix**: Set default:
   ```bash
   kubectl annotate storageclass ebs-gp3 storageclass.kubernetes.io/is-default-class=true
   ```

2. **Wrong provisioner name**
   ```yaml
   # ❌ Wrong
   provisioner: kubernetes.io/aws-ebs
   
   # ✅ Correct for CSI driver
   provisioner: ebs.csi.aws.com
   ```

3. **PVC doesn't specify StorageClass**
   ```yaml
   # If no default StorageClass, must specify explicitly
   spec:
     storageClassName: ebs-gp3
     accessModes: [ReadWriteOnce]
     resources:
       requests:
         storage: 10Gi
   ```

---

### Issue: Encryption Not Working

**Symptom**: Created volume but it's unencrypted.

**Check**:
```bash
aws ec2 describe-volumes --volume-ids vol-xxx --query "Volumes[0].Encrypted"
```

**Solution**: Add `encrypted: "true"` to StorageClass:
```yaml
parameters:
  type: gp3
  encrypted: "true"  # Must be string, not boolean
  # Optional: specify KMS key
  # kmsKeyId: "arn:aws:kms:region:account:key/xxx"
```

---

### Issue: IOPS/Throughput Not Applied

**Symptom**: Volume created with default IOPS instead of specified values.

**Check**:
```bash
aws ec2 describe-volumes --volume-ids vol-xxx --query "Volumes[0].[Iops,Throughput]"
```

**Cause**: Parameters must be strings:
```yaml
# ❌ Wrong - numbers
parameters:
  iops: 3000
  throughput: 125

# ✅ Correct - strings
parameters:
  iops: "3000"
  throughput: "125"
```

---

### Issue: CSI Driver Pods CrashLooping

**Check logs**:
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller --tail=50
```

**Common Causes**:

1. **Insufficient IAM permissions**
   Error: `ec2:DescribeVolumes: AccessDenied`
   
   **Fix**: Ensure all required permissions:
   - ec2:CreateVolume
   - ec2:AttachVolume
   - ec2:DetachVolume
   - ec2:DeleteVolume
   - ec2:DescribeVolumes
   - ec2:CreateSnapshot
   - ec2:DeleteSnapshot
   - ec2:DescribeSnapshots
   - ec2:CreateTags

2. **Node IAM role missing permissions**
   Node role needs `ec2:DescribeVolumes` at minimum.

3. **Network issues**
   - Nodes in private subnets need NAT Gateway for AWS API access

---

## for_each Issues (Advanced)

### Issue: for_each Requires Map, Got List

**Error Message**:
```
Error: Invalid for_each argument
The given "for_each" argument value is unsuitable: the "for_each" argument must be a map, or set of strings, and you have provided a value of type list of object.
```

**Cause**: Variable is a list, but for_each needs a map or set.

**Solution**: Convert list to map:
```hcl
# Variable definition
variable "addon_list" {
  type = list(object({
    name    = string
    version = optional(string)
  }))
}

# ❌ Wrong - can't iterate list directly
resource "aws_eks_addon" "addon" {
  for_each = var.addon_list
}

# ✅ Correct - convert to map
resource "aws_eks_addon" "addon" {
  for_each = { for addon in var.addon_list : addon.name => addon }
  
  addon_name    = each.value.name
  addon_version = each.value.version
}
```

**Key Pattern**: `{ for item in list : item.unique_key => item }`

---

### Issue: Duplicate Keys in for_each Map

**Error Message**:
```
Error: Duplicate object key
The map key "pod-identity-agent" has already been defined at ...
```

**Cause**: Multiple items in list have same key.

**Example**:
```hcl
addon_list = [
  { name = "vpc-cni" },
  { name = "vpc-cni" }  # ❌ Duplicate!
]

for_each = { for addon in var.addon_list : addon.name => addon }
# Results in: { "vpc-cni" = ..., "vpc-cni" = ... } ← Error!
```

**Solution**: Ensure keys are unique, or add index:
```hcl
# Option 1: Remove duplicates from list

# Option 2: Use index if duplicates needed
for_each = { for idx, addon in var.addon_list : "${idx}-${addon.name}" => addon }
```

---

### Issue: for_each Key Must Be Known at Plan Time

**Error Message**:
```
Error: Invalid for_each argument
The "for_each" map includes keys derived from resource attributes that cannot be determined until apply
```

**Cause**: Using computed values (like resource IDs) as keys.

**Example**:
```hcl
# ❌ Wrong - subnet ID not known until apply
for_each = { for subnet in aws_subnet.subnets : subnet.id => subnet }
```

**Solution**: Use index or static identifier:
```hcl
# ✅ Correct - use variable data (known at plan)
for_each = { for idx, subnet in var.subnets : tostring(idx) => subnet }
```

---

## Pod Identity vs IRSA Comparison

### When to Use Which?

| Feature | IRSA | Pod Identity |
|---------|------|--------------|
| **Release Date** | 2019 | 2023 |
| **Setup Complexity** | Higher | Lower |
| **EKS Version Required** | 1.13+ | 1.24+ |
| **Requires OIDC Provider** | Yes | No |
| **ServiceAccount Annotation** | Yes | No |
| **Use For** | Existing workloads | New workloads |

### Migration from IRSA to Pod Identity

**Not required** - Both work fine. But if migrating:

1. **Install pod-identity-agent**
2. **Create Pod Identity association**
3. **Remove ServiceAccount annotation**
4. **Remove OIDC provider from trust policy**
5. **Update trust policy to use `pods.eks.amazonaws.com`**

**No downtime**: Can run both simultaneously during migration.

---

## Quick Debugging Commands

### EBS CSI Driver
```bash
# Check CSI driver pods
kubectl get pods -n kube-system | grep ebs-csi

# CSI controller logs
kubectl logs -n kube-system -l app=ebs-csi-controller -f

# CSI node logs
kubectl logs -n kube-system -l app=ebs-csi-node -f

# Check PVC status
kubectl get pvc -A

# Describe PVC for events
kubectl describe pvc <pvc-name>

# Check PV
kubectl get pv

# Test IAM from CSI pod
kubectl exec -it -n kube-system <ebs-csi-controller-pod> -- aws sts get-caller-identity
```

### Pod Identity
```bash
# List Pod Identity associations
aws eks list-pod-identity-associations --cluster-name <cluster-name>

# Describe association
aws eks describe-pod-identity-association \
  --cluster-name <cluster-name> \
  --association-id <assoc-id>

# Check pod-identity-agent
kubectl get daemonset -n kube-system eks-pod-identity-agent

# Check agent logs
kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

### EBS Volumes
```bash
# List all EBS volumes
aws ec2 describe-volumes --region <region>

# Find volumes created by Kubernetes
aws ec2 describe-volumes \
  --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name"

# Check volume details
aws ec2 describe-volumes --volume-ids vol-xxx

# Check volume attachments
aws ec2 describe-volumes --volume-ids vol-xxx \
  --query "Volumes[0].Attachments"

# Count volumes per instance
aws ec2 describe-volumes \
  --filters "Name=attachment.instance-id,Values=<instance-id>" \
  --query "length(Volumes)"
```

---

## Getting Help

### Resources
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EBS CSI Driver Docs](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Terraform Community Forum](https://discuss.hashicorp.com/)
- [AWS re:Post](https://repost.aws/)

### Before Asking for Help
1. ✅ Read the error message completely
2. ✅ Run `terraform validate`
3. ✅ Check `terraform plan` output
4. ✅ Verify AWS credentials (`aws sts get-caller-identity`)
5. ✅ Check EKS cluster status in AWS Console
6. ✅ Check pod logs (`kubectl logs`)
7. ✅ Check events (`kubectl describe`)
8. ✅ Search error message on Google/StackOverflow
9. ✅ Check this troubleshooting guide

---

## AWS Load Balancer Controller Issues

### Issue: Subnet Auto-Discovery Failed

**Error Message**:
```
couldn't auto-discover subnets: unable to resolve at least one subnet (6 match VPC and tags: [kubernetes.io/role/elb], 6 tagged for other cluster)
```

**Cause**: Subnets are tagged for a different cluster name than your actual EKS cluster.

**Diagnosis**:
```bash
# Check your cluster name
kubectl config current-context

# Check subnet tags in AWS Console or CLI
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --query "Subnets[*].Tags"
```

**Solution**: Ensure subnet tags match exact cluster name:
```hcl
# In VPC module
tags = {
  "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"  # Must match!
  "kubernetes.io/role/elb" = "1"  # For public subnets
}
```

**Common Mistake**:
```hcl
# Wrong - pattern doesn't match actual cluster name
"kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"  # dev-eks-cluster

# Correct - use actual cluster name
"kubernetes.io/cluster/eks-cluster-dev" = "shared"
```

---

### Issue: ALB Controller Pods Not Starting

**Symptom**: Pods stuck in `Pending` or `CrashLoopBackOff`.

**Check pod status**:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Common Causes**:

1. **IRSA not configured correctly**
   ```bash
   # Check ServiceAccount annotation
   kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
   # Should have: eks.amazonaws.com/role-arn annotation
   ```

2. **IAM role trust policy wrong**
   - OIDC provider ARN mismatch
   - ServiceAccount name mismatch in condition

3. **IAM policy missing permissions**
   - Ensure using official AWS policy from GitHub

---

### Issue: Ingress Not Creating ALB

**Symptom**: Ingress created but no ALB appears, ADDRESS field empty.

**Check ingress status**:
```bash
kubectl get ingress <name>
kubectl describe ingress <name>
```

**Common Causes**:

1. **Missing `ingressClassName: alb`**
   ```yaml
   # ❌ Wrong
   spec:
     rules: [...]
   
   # ✅ Correct
   spec:
     ingressClassName: alb
     rules: [...]
   ```

2. **Wrong scheme annotation**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/scheme: internet-facing  # or internal
   ```

3. **Missing target-type annotation**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/target-type: ip  # Recommended for VPC CNI
   ```

4. **Backend service not found**
   - Check service exists and has endpoints
   ```bash
   kubectl get svc <service-name>
   kubectl get endpoints <service-name>
   ```

---

### Issue: IRSA Authentication Failure

**Error in controller logs**:
```
WebIdentityErr: failed to retrieve credentials
```

**Diagnosis**:
```bash
# Check OIDC provider exists
aws iam list-open-id-connect-providers

# Check role trust policy
aws iam get-role --role-name <role-name> --query "Role.AssumeRolePolicyDocument"
```

**Common Causes**:

1. **OIDC provider not created**
   ```hcl
   # Must exist in EKS module
   resource "aws_iam_openid_connect_provider" "eks" {
     url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
   }
   ```

2. **Wrong OIDC provider in trust policy**
   - ARN must match exactly
   - URL must not have `https://` prefix in condition

3. **ServiceAccount name mismatch**
   ```json
   // Trust policy condition
   "${oidc}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
   // Must match actual ServiceAccount name and namespace
   ```

---

### Issue: Helm Provider Can't Connect to Cluster

**Error Message**:
```
Error: Kubernetes cluster unreachable
```

**Causes and Solutions**:

1. **EKS cluster not ready**
   ```hcl
   # Add depends_on
   provider "helm" {
     # ...
   }
   
   module "alb_controller" {
     depends_on = [module.eks]
   }
   ```

2. **Data source referencing wrong cluster**
   ```hcl
   data "aws_eks_cluster" "cluster" {
     name = module.eks.cluster_name  # Must match actual cluster
   }
   ```

3. **AWS credentials expired**
   ```bash
   aws sts get-caller-identity
   ```

4. **Cluster endpoint not accessible**
   - Check cluster has public endpoint enabled
   - Or you're in private network with access

---

### Issue: Helm `set` Block Syntax Error

**Error Message**:
```
Error: Unsupported block type
```

**Cause**: Using old `set { }` syntax with new Helm provider.

**Solution**: Use array syntax:
```hcl
# ❌ Old syntax (deprecated)
set {
  name  = "key"
  value = "value"
}

# ✅ New syntax
set = [
  {
    name  = "key"
    value = "value"
  }
]
```

---

### Issue: ALB Target Health Check Failing

**Symptom**: ALB created but targets unhealthy.

**Diagnosis**:
```bash
# Check target group health in AWS Console
# Or via CLI
aws elbv2 describe-target-health --target-group-arn <arn>
```

**Common Causes**:

1. **Health check path wrong**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/healthcheck-path: /health  # Must exist
   ```

2. **Pod not listening on expected port**
   ```bash
   kubectl exec -it <pod> -- curl localhost:80/health
   ```

3. **Security group blocking health check**
   - ALB needs to reach pod on health check port

---

### Quick Debugging Commands

```bash
# Check ALB Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -f

# Check all ingresses
kubectl get ingress -A

# Describe specific ingress
kubectl describe ingress <name> -n <namespace>

# Check IngressClass
kubectl get ingressclass

# Check ServiceAccount
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml

# Check IAM role from pod
kubectl exec -it -n kube-system <controller-pod> -- aws sts get-caller-identity
```

---
