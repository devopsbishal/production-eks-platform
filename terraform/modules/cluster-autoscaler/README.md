# Cluster Autoscaler Module

This module deploys the Kubernetes Cluster Autoscaler to automatically adjust the number of nodes in EKS managed node groups based on pod resource requests.

## Overview

The Cluster Autoscaler watches for pods that fail to schedule due to insufficient resources and automatically scales up the appropriate node groups. It also scales down underutilized nodes to optimize costs.

## Features

- ✅ **Pod Identity Authentication** - Uses EKS Pod Identity (not IRSA)
- ✅ **Automatic Node Scaling** - Scales up when pods are pending, scales down when nodes are underutilized
- ✅ **Multi-Node Group Support** - Works with multiple node groups with different instance types
- ✅ **Scale-from-Zero** - Can scale node groups from 0 to N nodes
- ✅ **SPOT Instance Support** - Works with both On-Demand and SPOT instances
- ✅ **Custom IAM Policy** - Scoped permissions for autoscaling operations

## Architecture

```
┌─────────────────────────────────────────────┐
│          Kubernetes Cluster                 │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │   Cluster Autoscaler Pod           │    │
│  │   (kube-system namespace)          │    │
│  │                                    │    │
│  │   ServiceAccount: cluster-autoscaler│   │
│  └────────────────────────────────────┘    │
│              │                              │
│              │ Pod Identity                 │
│              ▼                              │
│  ┌────────────────────────────────────┐    │
│  │   EKS Pod Identity Agent           │    │
│  └────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
              │
              │ AWS Credentials
              ▼
┌─────────────────────────────────────────────┐
│          AWS IAM                            │
│                                             │
│  IAM Role: ClusterAutoscaler-{cluster}     │
│  Policy: AutoscalerPolicy                  │
│  Permissions:                              │
│    - autoscaling:DescribeAutoScalingGroups │
│    - autoscaling:SetDesiredCapacity        │
│    - ec2:DescribeInstances                 │
│    - eks:DescribeNodegroup                 │
└─────────────────────────────────────────────┘
```

## Prerequisites

1. **EKS Cluster** - Running EKS cluster with managed node groups
2. **Pod Identity Agent** - EKS addon `eks-pod-identity-agent` must be installed
3. **Node Group Tags** - Node groups must have Cluster Autoscaler tags:
   ```hcl
   tags = {
     "k8s.io/cluster-autoscaler/enabled"           = "true"
     "k8s.io/cluster-autoscaler/${cluster_name}"   = "owned"
   }
   ```

## Usage

### Basic Example

```hcl
module "cluster_autoscaler" {
  source = "../../modules/cluster-autoscaler"

  eks_cluster_name = "eks-cluster-dev"
  environment      = "dev"
  aws_region       = "us-west-2"

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}
```

### With Custom Configuration

```hcl
module "cluster_autoscaler" {
  source = "../../modules/cluster-autoscaler"

  eks_cluster_name = "eks-cluster-prod"
  environment      = "prod"
  aws_region       = "us-east-1"

  # Custom namespace
  namespace = "kube-system"

  # Custom Helm chart version
  helm_chart_version = "9.53.0"

  # Custom service account name
  service_account_name = "custom-autoscaler-sa"

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
    Team      = "platform-engineering"
  }
}
```

## Node Group Configuration

Your EKS node groups must be configured with proper tags and sizing:

```hcl
module "node_group_general" {
  source = "../../modules/eks-node-group"

  cluster_name = "eks-cluster-dev"
  node_group_name = "general"
  
  subnet_ids = ["subnet-xxx", "subnet-yyy"]

  # Scaling configuration
  min_size     = 2
  max_size     = 5
  desired_size = 3

  # Instance configuration
  capacity_type = "SPOT"
  instance_types = ["t3.medium", "t3.large"]

  # REQUIRED: Cluster Autoscaler tags
  tags = {
    "k8s.io/cluster-autoscaler/enabled"           = "true"
    "k8s.io/cluster-autoscaler/eks-cluster-dev"   = "owned"
  }
}
```

### Scale-from-Zero Configuration

To enable scale-from-zero capability:

```hcl
module "node_group_compute" {
  source = "../../modules/eks-node-group"

  cluster_name = "eks-cluster-dev"
  node_group_name = "compute"
  
  # Scale from 0 to 5 nodes
  min_size     = 0
  max_size     = 5
  desired_size = 0  # Start with zero nodes

  capacity_type = "SPOT"
  instance_types = ["c5.xlarge", "c5.2xlarge"]

  tags = {
    "k8s.io/cluster-autoscaler/enabled"         = "true"
    "k8s.io/cluster-autoscaler/eks-cluster-dev" = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/workload" = "compute-intensive"
  }
}
```

## How It Works

### Scale Up
1. Pod fails to schedule due to insufficient CPU/memory
2. Cluster Autoscaler detects pending pods
3. Calculates which node group can fit the pod
4. Increases `desired_size` of the appropriate node group
5. AWS creates new EC2 instances
6. Nodes join the cluster (typically 2-4 minutes)
7. Pending pods get scheduled

### Scale Down
1. Cluster Autoscaler monitors node utilization
2. If node is underutilized for `scale-down-unneeded-time` (default: 10 minutes)
3. Safely drains workloads to other nodes
4. Terminates the EC2 instance
5. Decreases node group size

### Node Group Selection

Cluster Autoscaler selects node groups based on:
- **Pod resource requests** (CPU, memory)
- **Node selectors and affinity rules**
- **Taints and tolerations**
- **Instance types** in the node group
- **Current utilization** of existing nodes

**Best Practice**: Group similar instance types together for predictable scheduling:
```hcl
# Good: Similar instance families
instance_types = ["c5.xlarge", "c5.2xlarge"]

# Avoid: Mixed families with different characteristics
instance_types = ["t3.small", "m5.large", "c5.2xlarge"]
```

## IAM Permissions

The module creates an IAM role with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": ["*"]
    }
  ]
}
```

## Monitoring

### Check Autoscaler Status

```bash
# View autoscaler logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

# Check current node count
kubectl get nodes

# View autoscaler events
kubectl get events -n kube-system --field-selector involvedObject.name=aws-cluster-autoscaler-*
```

### Common Log Messages

**Scale Up Triggered**:
```
Pod default/my-app-xxx triggered scale-up: 1 node(s) added to node group general
```

**Scale Down**:
```
Scale-down: node ip-192-168-x-x.compute.internal removed
```

**Cannot Scale**:
```
Pod didn't trigger scale-up (it wouldn't fit if a new node is added)
```

## Configuration Options

### Helm Chart Values

The module exposes these Helm chart configurations:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoDiscovery.clusterName` | EKS cluster name | Required |
| `rbac.serviceAccount.name` | ServiceAccount name | `cluster-autoscaler` |
| `awsRegion` | AWS region | Required |
| `replicaCount` | Number of replicas | `1` |
| `extraArgs.balance-similar-node-groups` | Balance across AZs | `true` |
| `extraArgs.skip-nodes-with-system-pods` | Skip nodes with system pods | `false` |

## Troubleshooting

### Pods Not Scaling Up

**Check 1**: Node group has available capacity
```bash
aws eks describe-nodegroup --cluster-name eks-cluster-dev --nodegroup-name general \
  --query 'nodegroup.scalingConfig'
```

**Check 2**: Node group has correct tags
```bash
aws eks list-tags-for-resource --resource-arn arn:aws:eks:region:account:nodegroup/cluster/nodegroup
```

**Check 3**: Pod resource requests are specified
```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
```

### Nodes Not Scaling Down

**Reasons**:
1. **System pods**: Nodes with kube-system pods won't scale down
2. **Local storage**: Pods with emptyDir volumes
3. **PodDisruptionBudget**: Prevents eviction
4. **Node utilization**: CPU/memory above threshold (50%)

**Solution**: Add annotation to pods that can be evicted:
```yaml
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "true"
```

### Scale-from-Zero Not Working

**Requirements**:
1. Node group `min_size = 0` and `desired_size = 0`
2. Node group tags include instance type or label information
3. Pods have explicit resource requests

**Add instance info to tags**:
```hcl
tags = {
  "k8s.io/cluster-autoscaler/node-template/label/workload" = "batch"
  "k8s.io/cluster-autoscaler/node-template/resources/ephemeral-storage" = "100Gi"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `eks_cluster_name` | Name of the EKS cluster | `string` | n/a | yes |
| `environment` | Environment (dev/staging/prod) | `string` | `"dev"` | no |
| `aws_region` | AWS region | `string` | n/a | yes |
| `namespace` | Kubernetes namespace | `string` | `"kube-system"` | no |
| `service_account_name` | ServiceAccount name | `string` | `"cluster-autoscaler"` | no |
| `helm_chart_version` | Helm chart version | `string` | `"9.53.0"` | no |
| `resource_tag` | Tags for AWS resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `iam_role_arn` | ARN of the IAM role |
| `service_account_name` | Name of the Kubernetes ServiceAccount |
| `namespace` | Kubernetes namespace |

## Best Practices

1. **Multiple Node Groups**: Create separate node groups for different workload types
   - General workloads: `t3.medium`, `t3.large`
   - Compute-intensive: `c5.xlarge`, `c5.2xlarge`
   - Memory-intensive: `r5.large`, `r5.xlarge`

2. **SPOT Instances**: Use SPOT for cost optimization (60-90% savings)
   - Always have multiple instance types for availability
   - Consider `capacity_type = "SPOT"` for non-critical workloads

3. **Resource Requests**: Always define resource requests on pods
   ```yaml
   resources:
     requests:
       cpu: "100m"
       memory: "128Mi"
   ```

4. **Node Group Sizing**:
   - `min_size`: Minimum nodes to keep running (usually 2 for HA)
   - `max_size`: Maximum nodes for cost control
   - `desired_size`: Initial node count

5. **Scale-from-Zero**: Use for batch/scheduled workloads
   - Saves costs when workloads aren't running
   - Accepts 2-4 minute startup delay

## Migration from Cluster Autoscaler to Karpenter

Cluster Autoscaler is suitable for:
- Simple scaling requirements
- EKS managed node groups
- Predictable workloads

Consider migrating to Karpenter for:
- **Faster provisioning** (30-60 seconds vs 2-4 minutes)
- **Better bin-packing** and cost optimization
- **Dynamic instance selection** based on actual pod requirements
- **Consolidation** and automatic rightsizing

## Version Compatibility

| Component | Version |
|-----------|---------|
| Kubernetes | 1.28+ |
| EKS | 1.28+ |
| Helm Chart | 9.53.0 |
| Cluster Autoscaler | 1.28.x |

## References

- [Cluster Autoscaler Documentation](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [AWS EKS Best Practices - Autoscaling](https://aws.github.io/aws-eks-best-practices/cluster-autoscaling/)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
