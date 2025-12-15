# EKS Node Group Module

This module creates EKS managed node groups with configurable scaling, instance types, and capacity types (On-Demand or SPOT).

## Overview

EKS managed node groups automate the provisioning and lifecycle management of nodes (EC2 instances) for your EKS cluster. This module provides a reusable way to create multiple node groups with different configurations for various workload types.

## Features

- ✅ **Managed Node Groups** - AWS handles node registration, updates, and termination
- ✅ **SPOT & On-Demand Support** - Choose capacity type per node group
- ✅ **Multiple Instance Types** - Specify multiple instance types for SPOT availability
- ✅ **Auto-scaling Configuration** - Define min, max, and desired node counts
- ✅ **Rolling Updates** - Controlled updates with max unavailable settings
- ✅ **Automatic Cluster Joining** - Nodes automatically register with EKS cluster
- ✅ **IAM Role Management** - Creates node IAM role with required policies

## Architecture

```
┌─────────────────────────────────────────────────┐
│          EKS Cluster                            │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │   Managed Node Group                     │  │
│  │                                          │  │
│  │   ┌────────┐  ┌────────┐  ┌────────┐  │  │
│  │   │ Node 1 │  │ Node 2 │  │ Node 3 │  │  │
│  │   │ t3.med │  │ t3.med │  │ t3.lrg │  │  │
│  │   └────────┘  └────────┘  └────────┘  │  │
│  │                                          │  │
│  │   Capacity: SPOT                         │  │
│  │   Min: 2, Max: 5, Desired: 3            │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
                     │
                     │ IAM Role
                     ▼
┌─────────────────────────────────────────────────┐
│          AWS IAM                                │
│                                                 │
│  Node Group IAM Role                           │
│  ├── AmazonEKSWorkerNodePolicy                 │
│  ├── AmazonEKS_CNI_Policy                      │
│  └── AmazonEC2ContainerRegistryReadOnly        │
└─────────────────────────────────────────────────┘
```

## Usage

### Basic Example - General Workloads

```hcl
module "node_group_general" {
  source = "../../modules/eks-node-group"

  eks_cluster_name = "eks-cluster-dev"
  node_group_name  = "general"
  environment      = "dev"
  
  subnet_ids = ["subnet-abc123", "subnet-def456", "subnet-ghi789"]

  node_group_scaling_config = {
    min_size     = 2
    max_size     = 5
    desired_size = 3
  }

  node_group_capacity_type  = "SPOT"
  node_group_instance_types = ["t3.medium", "t3.large"]

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}
```

### SPOT Instances with Multiple Types

```hcl
module "node_group_compute" {
  source = "../../modules/eks-node-group"

  eks_cluster_name = "eks-cluster-dev"
  node_group_name  = "compute"
  environment      = "dev"
  
  subnet_ids = module.vpc.private_subnet_ids

  node_group_scaling_config = {
    min_size     = 0  # Scale-from-zero capability
    max_size     = 10
    desired_size = 0
  }

  node_group_capacity_type  = "SPOT"
  node_group_instance_types = ["c5.xlarge", "c5.2xlarge", "c6i.xlarge"]

  node_group_update_config = {
    max_unavailable            = 2
    max_unavailable_percentage = 0
  }

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
    Workload  = "compute-intensive"
  }
}
```

### On-Demand Instances for Critical Workloads

```hcl
module "node_group_critical" {
  source = "../../modules/eks-node-group"

  eks_cluster_name = "eks-cluster-prod"
  node_group_name  = "critical"
  environment      = "prod"
  
  subnet_ids = module.vpc.private_subnet_ids

  node_group_scaling_config = {
    min_size     = 3  # Always maintain minimum for HA
    max_size     = 10
    desired_size = 3
  }

  node_group_capacity_type  = "ON_DEMAND"
  node_group_instance_types = ["m5.large"]

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
    Workload  = "critical"
  }
}
```

## Configuration Patterns

### SPOT Instances - Best Practices

**Always use multiple instance types** for SPOT availability:

```hcl
# ✅ Good: Multiple similar instance types
node_group_instance_types = ["t3.medium", "t3.large"]
node_group_instance_types = ["c5.xlarge", "c5.2xlarge", "c6i.xlarge"]
node_group_instance_types = ["m5.large", "m5a.large", "m5n.large"]

# ❌ Avoid: Single instance type (lower SPOT availability)
node_group_instance_types = ["t3.medium"]

# ❌ Avoid: Mixed families with different characteristics
node_group_instance_types = ["t3.small", "m5.2xlarge", "r5.xlarge"]
```

**Why multiple types?**
- Reduces SPOT interruption probability by 50-70%
- AWS can choose from available capacity
- Fallback if one type is unavailable

### Scaling Configuration

#### Always-On Node Group (HA)
```hcl
node_group_scaling_config = {
  min_size     = 2  # Maintain minimum for availability
  max_size     = 5
  desired_size = 3
}
```

#### Scale-from-Zero (Cost Optimization)
```hcl
node_group_scaling_config = {
  min_size     = 0  # Can scale to zero nodes
  max_size     = 10
  desired_size = 0  # Start with no nodes
}
```

**Use cases for scale-from-zero**:
- Batch processing jobs
- Scheduled workloads
- Development environments
- Non-critical background tasks

**Considerations**:
- 2-4 minute cold start when scaling from zero
- Requires Cluster Autoscaler or Karpenter
- Pods must have resource requests defined

### Update Configuration

```hcl
node_group_update_config = {
  max_unavailable            = 1  # Number of nodes
  max_unavailable_percentage = 0  # Or percentage (use one)
}
```

**Rolling Update Behavior**:
- `max_unavailable = 1`: Updates one node at a time
- `max_unavailable = 2`: Updates two nodes simultaneously (faster but more disruptive)
- During updates: Old nodes are cordoned → Pods drained → Node terminated → New node launched

## IAM Permissions

The module creates an IAM role for nodes with these AWS managed policies:

1. **AmazonEKSWorkerNodePolicy**
   - Allows nodes to connect to EKS cluster
   - EC2 describe permissions
   - EKS cluster connectivity

2. **AmazonEKS_CNI_Policy**
   - VPC CNI plugin operations
   - ENI management for pod networking
   - IP address assignment to pods

3. **AmazonEC2ContainerRegistryReadOnly**
   - Pull container images from ECR
   - Read-only registry access

### Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

## Integration with Cluster Autoscaler

To enable Cluster Autoscaler, add these tags when calling the module:

```hcl
module "node_group_autoscaled" {
  source = "../../modules/eks-node-group"
  
  # ... other configuration ...

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
    
    # Cluster Autoscaler tags
    "k8s.io/cluster-autoscaler/enabled"           = "true"
    "k8s.io/cluster-autoscaler/eks-cluster-dev"   = "owned"
    
    # Optional: Node template labels for scale-from-zero
    "k8s.io/cluster-autoscaler/node-template/label/workload" = "batch"
  }
}
```

## Integration with Karpenter

This module creates node groups that can work alongside Karpenter for running static workloads or the Karpenter controller itself.

## Subnet Selection

Node groups launch EC2 instances in the specified subnets. **Use private subnets** for security:

```hcl
# ✅ Good: Private subnets
subnet_ids = module.vpc.private_subnet_ids

# ❌ Avoid: Public subnets (security risk)
subnet_ids = module.vpc.public_subnet_ids
```

**Multi-AZ Deployment**:
- Provide subnets from multiple availability zones
- EKS distributes nodes across AZs for high availability
- Example: `["subnet-az-a", "subnet-az-b", "subnet-az-c"]`

## Monitoring

### Check Node Group Status

```bash
# List node groups
aws eks list-nodegroups --cluster-name eks-cluster-dev

# Describe node group
aws eks describe-nodegroup \
  --cluster-name eks-cluster-dev \
  --nodegroup-name eks-cluster-dev-general-node-group

# View nodes
kubectl get nodes -o wide

# Check node labels
kubectl get nodes --show-labels
```

### Node Group Health

```bash
# Check scaling config
aws eks describe-nodegroup \
  --cluster-name eks-cluster-dev \
  --nodegroup-name eks-cluster-dev-general-node-group \
  --query 'nodegroup.scalingConfig'

# Check node group status
aws eks describe-nodegroup \
  --cluster-name eks-cluster-dev \
  --nodegroup-name eks-cluster-dev-general-node-group \
  --query 'nodegroup.status'
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `node_group_name` | Name of the node group | `string` | n/a | yes |
| `eks_cluster_name` | EKS cluster name | `string` | `"test-eks-cluster"` | no |
| `environment` | Environment (dev/staging/prod) | `string` | `"dev"` | no |
| `subnet_ids` | List of subnet IDs for nodes | `list(string)` | `[]` | yes |
| `node_group_instance_types` | List of instance types | `list(string)` | n/a | yes |
| `node_group_capacity_type` | Capacity type (ON_DEMAND or SPOT) | `string` | `"SPOT"` | no |
| `node_group_scaling_config` | Scaling configuration | `object` | See below | no |
| `node_group_update_config` | Update configuration | `object` | See below | no |
| `resource_tag` | Tags for resources | `map(string)` | `{}` | no |

### Default Values

**Scaling Config**:
```hcl
{
  desired_size = 4
  max_size     = 6
  min_size     = 2
}
```

**Update Config**:
```hcl
{
  max_unavailable            = 1
  max_unavailable_percentage = 0
}
```

## Outputs

| Name | Description |
|------|-------------|
| `eks_node_group_status` | Status of the EKS node group (ACTIVE, CREATING, DELETING, etc.) |

## Troubleshooting

### Nodes Not Joining Cluster

**Symptom**: Node group created but nodes don't appear in `kubectl get nodes`.

**Check**:
```bash
# Verify node group status
aws eks describe-nodegroup --cluster-name eks-cluster-dev --nodegroup-name <name> \
  --query 'nodegroup.status'

# Check node group health
aws eks describe-nodegroup --cluster-name eks-cluster-dev --nodegroup-name <name> \
  --query 'nodegroup.health'
```

**Common causes**:
1. Incorrect IAM role permissions
2. Subnet has no route to internet (NAT gateway issue)
3. Security group blocking communication
4. EKS API endpoint not accessible from subnet

### SPOT Interruptions Too Frequent

**Solution**: Add more instance types to the node group:

```hcl
# Before: Single type (high interruption risk)
node_group_instance_types = ["c5.xlarge"]

# After: Multiple types (lower interruption risk)
node_group_instance_types = ["c5.xlarge", "c5.2xlarge", "c6i.xlarge"]
```

### Nodes Stuck in "NotReady" State

**Check**:
```bash
kubectl describe node <node-name>
```

**Common causes**:
1. VPC CNI not working (check `aws-node` DaemonSet)
2. kubelet not starting
3. Insufficient instance resources
4. Node IAM role missing CNI policy

### Node Group Update Failed

**Check**:
```bash
aws eks describe-nodegroup --cluster-name eks-cluster-dev --nodegroup-name <name> \
  --query 'nodegroup.health'
```

**Common causes**:
1. PodDisruptionBudget preventing pod eviction
2. Insufficient capacity to drain nodes
3. Pods with local storage preventing migration

**Fix**: Adjust PodDisruptionBudget or increase `max_unavailable`.

## Best Practices

### 1. Node Group Sizing Strategy

Create separate node groups for different workload types:

```hcl
# General purpose - always-on
module "node_group_general" {
  node_group_instance_types = ["t3.medium", "t3.large"]
  node_group_capacity_type  = "SPOT"
  node_group_scaling_config = {
    min_size     = 2
    max_size     = 5
    desired_size = 3
  }
}

# Compute-intensive - scale-from-zero
module "node_group_compute" {
  node_group_instance_types = ["c5.xlarge", "c5.2xlarge"]
  node_group_capacity_type  = "SPOT"
  node_group_scaling_config = {
    min_size     = 0
    max_size     = 10
    desired_size = 0
  }
}

# Memory-intensive
module "node_group_memory" {
  node_group_instance_types = ["r5.large", "r5.xlarge"]
  node_group_capacity_type  = "SPOT"
  node_group_scaling_config = {
    min_size     = 1
    max_size     = 5
    desired_size = 2
  }
}
```

### 2. SPOT vs On-Demand Strategy

- **Development**: 100% SPOT (cost savings)
- **Staging**: 80% SPOT, 20% On-Demand (stability)
- **Production**: 50% SPOT, 50% On-Demand (balance)
- **Critical**: 100% On-Demand (reliability)

### 3. Instance Type Selection

**Match workload characteristics**:

```hcl
# General purpose (balanced CPU/memory)
instance_types = ["t3.medium", "t3.large"]  # 2:4 or 2:8 GB ratio

# Compute optimized (high CPU)
instance_types = ["c5.xlarge", "c5.2xlarge"]  # 4:8 or 8:16 GB ratio

# Memory optimized (high memory)
instance_types = ["r5.large", "r5.xlarge"]  # 2:16 or 4:32 GB ratio
```

### 4. Subnet Strategy

- **Use private subnets** with NAT gateway
- **Multi-AZ deployment** for high availability
- **Separate subnets** for different node groups (optional)

### 5. Update Strategy

**Conservative** (production):
```hcl
node_group_update_config = {
  max_unavailable = 1  # One node at a time
}
```

**Aggressive** (development):
```hcl
node_group_update_config = {
  max_unavailable_percentage = 50  # 50% of nodes simultaneously
}
```

## Managed vs Self-Managed Node Groups

This module uses **EKS Managed Node Groups**:

| Feature | Managed Node Groups | Self-Managed |
|---------|-------------------|--------------|
| **Setup** | Simple (AWS handles) | Complex (bootstrap script) |
| **Updates** | AWS managed | Manual |
| **Node Registration** | Automatic | Manual configuration |
| **Cost** | No additional cost | Same EC2 cost |
| **Flexibility** | Standard AMIs | Custom AMIs possible |
| **Recommendation** | ✅ Use for most cases | Use only if custom AMI needed |

## Version Compatibility

| Component | Version |
|-----------|---------|
| Terraform | >= 1.5.7 |
| AWS Provider | >= 6.0 |
| Kubernetes | 1.28+ |
| EKS | 1.28+ |

## Migration from Self-Managed

If migrating from self-managed node groups:

1. Create managed node group alongside self-managed
2. Cordon self-managed nodes: `kubectl cordon <node>`
3. Drain workloads: `kubectl drain <node> --ignore-daemonsets`
4. Delete self-managed ASG
5. Remove self-managed Terraform resources

## References

- [EKS Managed Node Groups Documentation](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [EKS Node IAM Role](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html)
- [SPOT Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
