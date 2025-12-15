# Karpenter Module

This module deploys Karpenter, a flexible, high-performance Kubernetes node autoscaler that provisions right-sized compute resources in response to changing application load.

## Overview

Karpenter simplifies Kubernetes infrastructure with the right nodes at the right time. It observes incoming pods and launches the optimal compute resources to handle them. Unlike Cluster Autoscaler which works with pre-defined node groups, Karpenter dynamically selects instance types based on actual workload requirements.

## Features

- ✅ **Fast Provisioning** - Launches nodes in ~30-60 seconds (vs 2-4 minutes for Cluster Autoscaler)
- ✅ **Dynamic Instance Selection** - Chooses optimal instance types based on pod requirements
- ✅ **Consolidation** - Automatically replaces nodes with cheaper/smaller instances
- ✅ **SPOT Support** - Native SPOT interruption handling with SQS queue
- ✅ **Pod Identity Authentication** - Uses EKS Pod Identity (not IRSA)
- ✅ **Terraform AWS Module** - Uses official `terraform-aws-modules/eks/aws//modules/karpenter`
- ✅ **Multiple NodePools** - Support for different workload classes
- ✅ **Scale to Zero** - Can scale down to zero nodes when idle

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                         │
│                                                               │
│  ┌────────────────────────────────────────────────────┐      │
│  │   Karpenter Controller                             │      │
│  │   (karpenter namespace)                            │      │
│  │                                                    │      │
│  │   ServiceAccount: karpenter                        │      │
│  │   Replicas: 2 (HA)                                 │      │
│  └────────────────────────────────────────────────────┘      │
│              │                              │                 │
│              │ Pod Identity                 │ Reads           │
│              ▼                              ▼                 │
│  ┌─────────────────────┐      ┌──────────────────────┐      │
│  │ Pod Identity Agent  │      │   NodePool CRDs      │      │
│  └─────────────────────┘      │   EC2NodeClass CRDs  │      │
│                                └──────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
              │                              │
              │ AWS Credentials              │ Provisions
              ▼                              ▼
┌──────────────────────────────────────────────────────────────┐
│                         AWS                                   │
│                                                               │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────┐  │
│  │ IAM Role       │  │ SQS Queue       │  │ EventBridge  │  │
│  │ KarpenterCtrl  │  │ Interruptions   │  │ Rules        │  │
│  └────────────────┘  └─────────────────┘  └──────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ EC2 Instances (provisioned by Karpenter)               │  │
│  │ - Dynamic instance type selection                      │  │
│  │ - SPOT & On-Demand support                            │  │
│  │ - Instance Profile: KarpenterNodeRole                 │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **EKS Cluster** - Running EKS cluster
2. **Pod Identity Agent** - EKS addon `eks-pod-identity-agent` must be installed
3. **VPC Resources Tagged** - Subnets and security groups must have Karpenter discovery tags:
   ```hcl
   tags = {
     "karpenter.sh/discovery" = "eks-cluster-name"
   }
   ```
4. **Initial Node Group** - At least one node group to run Karpenter controller itself

## Usage

### Basic Example

```hcl
module "karpenter" {
  source = "../../modules/karpenter"

  eks_cluster_name     = "eks-cluster-dev"
  eks_cluster_endpoint = module.eks.eks_cluster_endpoint
  environment          = "dev"
  aws_region           = "us-west-2"

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
  }
}
```

### Complete Example with Custom Configuration

```hcl
module "karpenter" {
  source = "../../modules/karpenter"

  eks_cluster_name     = "eks-cluster-prod"
  eks_cluster_endpoint = module.eks.eks_cluster_endpoint
  environment          = "prod"
  aws_region           = "us-east-1"

  # Custom namespace
  namespace = "karpenter"

  # Custom Helm chart version
  helm_chart_version = "1.0.0"

  # Custom service account
  service_account_name = "karpenter"

  resource_tag = {
    ManagedBy = "Terraform"
    Project   = "production-eks-platform"
    Team      = "platform-engineering"
  }
}
```

## VPC Tagging Requirements

Karpenter discovers subnets and security groups using tags. You must tag your resources:

### Subnets

```hcl
resource "aws_subnet" "private" {
  # ... subnet configuration ...

  tags = {
    "karpenter.sh/discovery" = "eks-cluster-dev"  # Required
    "kubernetes.io/role/internal-elb" = "1"       # For private subnets
  }
}
```

### Security Groups

```hcl
resource "aws_ec2_tag" "cluster_sg_tag" {
  resource_id = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "eks-cluster-dev"
}
```

## NodePool Configuration

After deploying the module, create NodePool and EC2NodeClass resources to define provisioning behavior.

### Example NodePool - General Workloads

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]  # Use SPOT instances
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]  # Compute, general, memory-optimized
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]  # Generation 3 and above
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h  # Recycle nodes after 30 days
  limits:
    cpu: 1000  # Max 1000 CPUs across all nodes in this pool
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m  # Consolidate after 1 minute of underutilization
```

### Example EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-eks-cluster-dev"
  amiSelectorTerms:
    - alias: "al2023"  # Amazon Linux 2023
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "eks-cluster-dev"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "eks-cluster-dev"
```

### NodePool - SPOT for Batch Workloads

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: batch
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c"]  # Compute-optimized only
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c5.xlarge", "c5.2xlarge", "c6i.xlarge"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      taints:
        - key: workload
          value: batch
          effect: NoSchedule
  limits:
    cpu: 500
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s  # Aggressive scale down for batch
```

## How Karpenter Works

### Provisioning Decision Flow

1. **Pod Pending**: Kubernetes scheduler cannot place a pod
2. **Karpenter Observes**: Detects unschedulable pod
3. **Requirements Analysis**: 
   - Pod resource requests (CPU, memory, storage)
   - Node selectors and affinity rules
   - Taints and tolerations
   - Topology constraints
4. **Instance Selection**:
   - Queries AWS for available instance types
   - Scores based on cost, availability, and fit
   - Selects optimal instance (usually SPOT if available)
5. **Node Launch**: Creates EC2 instance with proper IAM role
6. **Node Registration**: Node joins cluster (~30-60 seconds)
7. **Pod Scheduling**: Kubernetes scheduler places pod on new node

### Consolidation

Karpenter continuously looks for opportunities to:
- **Delete empty nodes** (no workloads running)
- **Replace nodes** with cheaper/smaller instances
- **Merge workloads** onto fewer nodes

**Example**: 3 nodes with 30% utilization each → Consolidate to 2 nodes with 45% utilization

### SPOT Interruption Handling

When AWS sends SPOT interruption notice:
1. SQS queue receives interruption event
2. Karpenter controller processes message
3. Cordons and drains the node
4. Provisions replacement node (if needed)
5. Workloads gracefully migrate

## What the Module Creates

The module uses `terraform-aws-modules/eks/aws//modules/karpenter` and creates:

### IAM Resources
- **Controller IAM Role**: For Karpenter controller pod (EC2, IAM, pricing permissions)
- **Node IAM Role**: For EC2 instances provisioned by Karpenter
- **Instance Profile**: Associated with Node IAM role
- **Pod Identity Association**: Links ServiceAccount to controller IAM role

### Networking Resources
- **SQS Queue**: For SPOT interruption notifications
- **EventBridge Rules**: 
  - SPOT instance interruption warnings
  - Instance state changes
  - Rebalance recommendations
  - Scheduled maintenance events

### EKS Resources
- **Access Entry**: Allows nodes to join the cluster
- **Helm Release**: Deploys Karpenter controller

## Configuration Options

### Module Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `eks_cluster_name` | EKS cluster name | Required |
| `eks_cluster_endpoint` | EKS cluster endpoint URL | Required |
| `environment` | Environment name | `"dev"` |
| `aws_region` | AWS region | Required |
| `namespace` | Kubernetes namespace | `"karpenter"` |
| `service_account_name` | ServiceAccount name | `"karpenter"` |
| `helm_chart_version` | Helm chart version | `"1.0.0"` |

### Helm Values

The module sets these Helm values:

```hcl
set = [
  {
    name  = "settings.clusterName"
    value = "eks-cluster-dev"
  },
  {
    name  = "settings.clusterEndpoint"
    value = "https://xxx.eks.amazonaws.com"
  },
  {
    name  = "settings.interruptionQueue"
    value = "karpenter-eks-cluster-dev"
  },
  {
    name  = "controller.resources.requests.cpu"
    value = "1"
  },
  {
    name  = "controller.resources.requests.memory"
    value = "1Gi"
  }
]
```

## Monitoring

### Check Karpenter Status

```bash
# View Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check NodePools
kubectl get nodepools

# Check EC2NodeClasses
kubectl get ec2nodeclasses

# View nodes managed by Karpenter
kubectl get nodes -l karpenter.sh/nodepool
```

### Common Log Messages

**Node Provisioning**:
```json
{"level":"INFO","message":"launched node","node":"i-0123456789","instance-type":"m5.large","capacity-type":"spot"}
```

**Consolidation**:
```json
{"level":"INFO","message":"consolidation delete","node":"ip-192-168-1-1","reason":"underutilized"}
```

**SPOT Interruption**:
```json
{"level":"WARN","message":"interruption received","node":"i-0123456789","action":"terminate"}
```

## Troubleshooting

### NodePool Not Ready

**Symptom**: `kubectl get nodepool` shows `READY=False`

**Check EC2NodeClass status**:
```bash
kubectl describe ec2nodeclass default
```

**Common Issues**:
1. **Subnets not found**: Missing `karpenter.sh/discovery` tag on subnets
2. **Security groups not found**: Missing tag on security group
3. **AMI not found**: Invalid AMI alias (use `al2023` or `al2023@latest`)
4. **IAM role not found**: Check Node IAM role exists

### Nodes Not Provisioning

**Check 1**: Pod has resource requests
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
```

**Check 2**: NodePool has available capacity
```bash
kubectl get nodepool -o yaml | grep limits -A 5
```

**Check 3**: Instance types are available
```bash
# Check Karpenter logs for pricing/availability issues
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep "instance type"
```

**Check 4**: Pod doesn't have conflicting constraints
```bash
# Node selectors, affinity, tolerations might prevent scheduling
kubectl describe pod <pod-name>
```

### SPOT Interruptions Not Handled

**Verify SQS queue**:
```bash
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name karpenter-eks-cluster-dev --query 'QueueUrl' --output text) \
  --attribute-names All
```

**Check EventBridge rules**:
```bash
aws events list-rules --name-prefix Karpenter
```

### Consolidation Too Aggressive

**Adjust consolidation policy** in NodePool:
```yaml
disruption:
  consolidationPolicy: WhenEmpty  # Only when completely empty
  consolidateAfter: 5m             # Wait 5 minutes before consolidating
```

**Prevent specific nodes from consolidation**:
```yaml
# Add annotation to node
kubectl annotate node <node-name> karpenter.sh/do-not-disrupt=true
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `eks_cluster_name` | EKS cluster name | `string` | n/a | yes |
| `eks_cluster_endpoint` | EKS cluster API endpoint | `string` | n/a | yes |
| `environment` | Environment name | `string` | `"dev"` | no |
| `aws_region` | AWS region | `string` | n/a | yes |
| `namespace` | Kubernetes namespace | `string` | `"karpenter"` | no |
| `service_account_name` | ServiceAccount name | `string` | `"karpenter"` | no |
| `helm_chart_version` | Helm chart version | `string` | `"1.0.0"` | no |
| `resource_tag` | Tags for resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `iam_role_arn` | Controller IAM role ARN |
| `node_iam_role_arn` | Node IAM role ARN |
| `node_iam_role_name` | Node IAM role name |
| `instance_profile_name` | EC2 instance profile name |
| `queue_name` | SQS queue name |
| `queue_url` | SQS queue URL |

## Best Practices

### 1. NodePool Design

Create multiple NodePools for different workload classes:

```yaml
# General workloads - flexible instance types
NodePool: general (spot, c/m/r families)

# Batch jobs - compute optimized, aggressive consolidation
NodePool: batch (spot, c family only)

# Critical workloads - on-demand instances
NodePool: critical (on-demand, specific instance types)
```

### 2. Instance Type Selection

**Good**: Flexible with multiple families
```yaml
instance-category: ["c", "m", "r"]
instance-generation: Gt "2"
```

**Better**: Constrain by specific types when needed
```yaml
instance-type: ["c5.xlarge", "c5.2xlarge", "m5.xlarge"]
```

### 3. SPOT Usage

- **Use SPOT by default** for 60-90% cost savings
- **Have On-Demand NodePool** as fallback for critical workloads
- **Multiple instance types** improve SPOT availability

### 4. Resource Requests

Always define resource requests on pods:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "200m"
    memory: "256Mi"
```

### 5. Node Disruption

**For stateful workloads**:
```yaml
# Add to pod spec
spec:
  terminationGracePeriodSeconds: 120
  
# Or prevent disruption
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"
```

### 6. Consolidation Tuning

**Aggressive** (for batch/dev):
```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 30s
```

**Conservative** (for production):
```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 5m
```

## Cluster Autoscaler vs Karpenter

| Feature | Cluster Autoscaler | Karpenter |
|---------|-------------------|-----------|
| **Provisioning Speed** | 2-4 minutes | 30-60 seconds |
| **Instance Selection** | Fixed node groups | Dynamic, optimal |
| **Bin Packing** | Basic | Advanced |
| **Consolidation** | Limited | Automatic & continuous |
| **SPOT Handling** | Basic | Native with SQS |
| **Configuration** | Node group based | Flexible requirements |
| **Cost Optimization** | Good | Excellent |
| **Complexity** | Low | Medium |

**When to use Cluster Autoscaler**:
- Simple scaling needs
- Existing node group infrastructure
- Team familiar with ASG model

**When to use Karpenter**:
- Dynamic workloads
- Cost optimization priority
- Fast scaling requirements
- Modern cloud-native approach

## Version Compatibility

| Component | Version |
|-----------|---------|
| Kubernetes | 1.28+ |
| EKS | 1.28+ |
| Karpenter | v1.0.0+ |
| Terraform AWS EKS Module | 20.31+ |

## Migration Path

**From Cluster Autoscaler to Karpenter**:

1. Deploy Karpenter alongside Cluster Autoscaler
2. Create Karpenter NodePools
3. Test with non-critical workloads
4. Gradually migrate workloads
5. Remove Cluster Autoscaler when confident

**Coexistence**: You can run both simultaneously, but disable Cluster Autoscaler on node groups managed by Karpenter.

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Karpenter Best Practices](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [Terraform AWS EKS Karpenter Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/karpenter)
- [Karpenter GitHub Repository](https://github.com/aws/karpenter-provider-aws)
