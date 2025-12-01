# EKS Module

A production-ready AWS EKS module with managed node groups, IAM roles, and API-based access management.

## Features

- 🚀 **Managed Node Groups** - Auto-scaling EC2 worker nodes with configurable instance types
- 🔐 **API Authentication Mode** - Modern EKS access management via Access Entries (no ConfigMap)
- 👥 **Flexible Access Control** - Grant IAM users/roles cluster access with fine-grained policies
- 📊 **Full Cluster Logging** - API, audit, authenticator, controller manager, and scheduler logs
- 💰 **Cost Optimization** - Support for Spot instances and configurable scaling
- 🏷️ **Consistent Tagging** - All resources tagged for cost tracking and management

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         EKS Cluster                                  │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │    │
│  │  │  Control Plane  │  │   API Server    │  │  etcd (managed) │      │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Managed Node Group                              │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐         │    │
│  │  │  Node 1   │  │  Node 2   │  │  Node 3   │  │  Node N   │         │    │
│  │  │ (t3.med)  │  │ (t3.med)  │  │ (t3.med)  │  │ (t3.med)  │         │    │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        Access Entries                                │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │ IAM User 1  │  │ IAM Role 1  │  │ IAM User N  │                  │    │
│  │  │ (Admin)     │  │ (Developer) │  │ (ReadOnly)  │                  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Usage

### Basic Usage

```hcl
module "eks" {
  source           = "../../modules/eks"
  eks_cluster_name = "my-cluster"
  environment      = "dev"
  subnet_ids       = module.vpc.private_subnet_ids
}
```

### Production Configuration

```hcl
module "eks" {
  source              = "../../modules/eks"
  eks_cluster_name    = "prod-cluster"
  environment         = "prod"
  eks_version         = "1.34"
  authentication_mode = "API"
  subnet_ids          = module.vpc.private_subnet_ids

  # Node group configuration
  node_group_scaling_config = {
    desired_size = 6
    max_size     = 10
    min_size     = 3
  }

  node_group_instance_types = ["t3.large", "t3.xlarge"]
  node_group_capacity_type  = "ON_DEMAND"

  # Access entries
  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::123456789012:user/admin"
    }
    developers = {
      principal_arn     = "arn:aws:iam::123456789012:role/DeveloperRole"
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    }
  }

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-platform"
    CostCenter = "engineering"
  }
}
```

### Cost-Optimized (Dev/Staging)

```hcl
module "eks" {
  source           = "../../modules/eks"
  eks_cluster_name = "dev-cluster"
  environment      = "dev"
  subnet_ids       = module.vpc.private_subnet_ids

  node_group_scaling_config = {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  node_group_instance_types = ["t3.medium"]
  node_group_capacity_type  = "SPOT"  # Up to 90% savings

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::123456789012:user/admin"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `eks_cluster_name` | Name of the EKS cluster | `string` | `"test-eks-cluster"` | no |
| `environment` | Environment name (dev/staging/prod) | `string` | `"dev"` | no |
| `eks_version` | Kubernetes version for the cluster | `string` | `"1.34"` | no |
| `authentication_mode` | Authentication mode (API or CONFIG_MAP) | `string` | `"API"` | no |
| `subnet_ids` | List of subnet IDs for the cluster | `list(string)` | `[]` | yes |
| `node_group_scaling_config` | Scaling configuration for node group | `object` | See below | no |
| `node_group_update_config` | Update configuration for node group | `object` | See below | no |
| `node_group_instance_types` | List of instance types for nodes | `list(string)` | `["t3.medium"]` | no |
| `node_group_capacity_type` | Capacity type (ON_DEMAND or SPOT) | `string` | `"SPOT"` | no |
| `access_entries` | Map of IAM principals for cluster access | `map(object)` | `{}` | no |
| `resource_tag` | Common tags for all resources | `map(string)` | See below | no |

### node_group_scaling_config Default

```hcl
{
  desired_size = 4
  max_size     = 6
  min_size     = 2
}
```

### node_group_update_config Default

```hcl
{
  max_unavailable            = 1
  max_unavailable_percentage = 0
}
```

### access_entries Structure

```hcl
access_entries = {
  entry_key = {
    principal_arn     = "arn:aws:iam::ACCOUNT_ID:user/USERNAME"  # Required
    type              = "STANDARD"                                 # Optional
    policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"  # Optional
    access_scope_type = "cluster"                                  # Optional: cluster or namespace
    namespaces        = []                                         # Optional: for namespace scope
  }
}
```

### Available Access Policies

| Policy | Description |
|--------|-------------|
| `AmazonEKSClusterAdminPolicy` | Full admin access including IAM permissions |
| `AmazonEKSAdminPolicy` | Admin access without IAM permissions |
| `AmazonEKSEditPolicy` | Create/edit/delete most resources |
| `AmazonEKSViewPolicy` | Read-only access to resources |

### resource_tag Default

```hcl
{
  ManagedBy = "Terraform"
  Project   = "production-eks-platform"
}
```

## Outputs

| Name | Description |
|------|-------------|
| `eks_cluster_endpoint` | The endpoint URL for the EKS cluster API server |
| `eks_cluster_status` | The status of the EKS cluster |
| `eks_node_group_status` | The status of the managed node group |

## IAM Roles Created

### Cluster Role

The module creates an IAM role for the EKS cluster with the following policy:

- `AmazonEKSClusterPolicy` - Required for EKS cluster operations

### Node Group Role

The module creates an IAM role for worker nodes with the following policies:

| Policy | Purpose |
|--------|---------|
| `AmazonEKSWorkerNodePolicy` | Allows nodes to connect to EKS |
| `AmazonEKS_CNI_Policy` | Allows VPC CNI plugin to manage networking |
| `AmazonEC2ContainerRegistryReadOnly` | Allows pulling images from ECR |

## Access Management

This module uses the **API authentication mode** (recommended for new clusters) instead of the legacy ConfigMap-based authentication.

### How Access Entries Work

```
IAM Principal (User/Role)
         │
         ▼
┌─────────────────────┐
│   Access Entry      │  ← Created by aws_eks_access_entry
│   (principal_arn)   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   Access Policy     │  ← Associated by aws_eks_access_policy_association
│   Association       │
│   (policy_arn)      │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   Kubernetes RBAC   │  ← Automatically mapped
│   Permissions       │
└─────────────────────┘
```

### Connecting to the Cluster

After applying, connect to your cluster:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name <cluster-name>

# Verify connection
kubectl get nodes
```

### Why API Mode Over ConfigMap?

| Feature | API Mode | ConfigMap Mode |
|---------|----------|----------------|
| Management | AWS Console/CLI/Terraform | kubectl only |
| Audit | CloudTrail integration | Limited |
| Recovery | AWS API available | Need cluster access |
| Best Practice | ✅ Recommended | Legacy |

## Cluster Logging

All control plane log types are enabled:

| Log Type | Description |
|----------|-------------|
| `api` | API server logs |
| `audit` | Audit logs for API requests |
| `authenticator` | Authentication logs |
| `controllerManager` | Controller manager logs |
| `scheduler` | Scheduler logs |

Logs are sent to CloudWatch Logs at: `/aws/eks/<cluster-name>/cluster`

## Cost Estimation

### Cluster Costs (Fixed)

| Component | Cost |
|-----------|------|
| EKS Cluster | $0.10/hour (~$73/month) |

### Node Group Costs (Variable)

| Instance Type | On-Demand/hour | Spot/hour* | Monthly (4 nodes) |
|---------------|----------------|------------|-------------------|
| t3.medium | $0.0416 | ~$0.0125 | $120 / $36 |
| t3.large | $0.0832 | ~$0.025 | $240 / $72 |
| t3.xlarge | $0.1664 | ~$0.05 | $480 / $144 |

*Spot pricing varies by AZ and demand

### Example Monthly Costs

| Environment | Nodes | Instance | Capacity | Est. Cost |
|-------------|-------|----------|----------|-----------|
| Dev | 2 | t3.medium | SPOT | ~$109/mo |
| Staging | 4 | t3.medium | SPOT | ~$145/mo |
| Production | 6 | t3.large | ON_DEMAND | ~$553/mo |

## Resources Created

- 1 EKS Cluster
- 1 EKS Managed Node Group
- 1 IAM Role (Cluster)
- 1 IAM Role (Node Group)
- 1 IAM Policy Attachment (Cluster)
- 3 IAM Policy Attachments (Node Group)
- N Access Entries (based on `access_entries` variable)
- N Access Policy Associations (based on `access_entries` variable)

## Best Practices

### Security

- ✅ Use private subnets for node groups
- ✅ Enable all control plane logging
- ✅ Use API authentication mode
- ✅ Grant least-privilege access via access policies
- ✅ Regularly rotate node groups for security patches

### Cost Optimization

- 💰 Use SPOT instances for non-production
- 💰 Right-size node instance types
- 💰 Set appropriate min/max scaling limits
- 💰 Use Cluster Autoscaler or Karpenter

### High Availability

- 🏗️ Deploy nodes across multiple AZs (via subnet_ids)
- 🏗️ Set min_size >= 2 for production
- 🏗️ Use multiple instance types for Spot availability

## Troubleshooting

### "Your current IAM principal doesn't have access"

This means you need an Access Entry. Add your IAM principal to the `access_entries` variable:

```hcl
access_entries = {
  my_user = {
    principal_arn = "arn:aws:iam::ACCOUNT_ID:user/MY_USER"
  }
}
```

### Nodes not joining the cluster

1. Verify nodes are in a private subnet with NAT Gateway access
2. Check node group IAM role has required policies
3. Verify subnet tags include `kubernetes.io/cluster/<cluster-name> = shared`

### Cannot connect with kubectl

```bash
# Ensure kubeconfig is updated
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Verify current context
kubectl config current-context

# Check your IAM identity
aws sts get-caller-identity
```

## Related Documentation

- [VPC Module](../vpc/Readme.md)
- [Architecture Decision Records](../../../docs/DECISIONS.md)
- [Learning Journal](../../../docs/LEARNINGS.md)
- [Changelog](../../../docs/CHANGELOG.md)
- [Troubleshooting Guide](../../../docs/TROUBLESHOOTING.md)

## License

This module is part of the [production-eks-platform](https://github.com/devopsbishal/production-eks-platform) project.
