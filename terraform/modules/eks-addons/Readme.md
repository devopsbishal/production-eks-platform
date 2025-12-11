# EKS Add-ons Module

This module manages native EKS add-ons using the AWS EKS Add-on API.

## Purpose

EKS add-ons are AWS-managed Kubernetes operational software that extend the functionality of your cluster. This module provides a streamlined way to install and manage multiple add-ons.

## What are EKS Add-ons?

Native EKS add-ons are:
- **AWS-managed**: Automatically updated and patched
- **Integrated**: Deep integration with EKS control plane
- **Validated**: Tested for compatibility with EKS versions
- **Lifecycle-managed**: Version upgrades handled by AWS

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EKS Control Plane                             │
│                                                                  │
│  Manages and monitors add-on lifecycle                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Worker Nodes                                  │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ vpc-cni          │  │ kube-proxy       │                    │
│  │ (networking)     │  │ (networking)     │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ coredns          │  │ pod-identity-    │                    │
│  │ (DNS)            │  │ agent            │                    │
│  └──────────────────┘  └──────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

## Available Add-ons

| Add-on | Purpose | Required For |
|--------|---------|--------------|
| `vpc-cni` | Pod networking | All clusters |
| `coredns` | DNS resolution | All clusters |
| `kube-proxy` | Network proxy | All clusters |
| `eks-pod-identity-agent` | Pod Identity feature | EBS CSI, other Pod Identity workloads |
| `aws-ebs-csi-driver` | EBS volume provisioning | StatefulSets with persistent storage |
| `snapshot-controller` | Volume snapshots | Backup/restore workflows |

## Features

- **Declarative Management**: Define add-ons as code
- **Version Control**: Pin or auto-update add-on versions
- **Conflict Resolution**: Handle configuration conflicts automatically
- **Tagging**: Consistent resource tagging across add-ons

## Usage

```hcl
module "eks_addon" {
  source = "../../modules/eks-addons"

  cluster_name = module.eks.cluster_name
  environment  = "dev"
  
  addon_list = [
    {
      name              = "eks-pod-identity-agent"
      version           = "v1.0.0-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    },
    {
      name    = "vpc-cni"
      version = "v1.18.0-eksbuild.1"
    },
    {
      name = "coredns"
      # version omitted = latest compatible version
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | Name of the EKS cluster | `string` | n/a | yes |
| `addon_list` | List of add-ons to install | `list(object)` | n/a | yes |
| `environment` | Environment name | `string` | `"dev"` | no |
| `resource_tag` | Common tags for resources | `map(string)` | `{}` | no |

### Add-on Object Structure

```hcl
{
  name              = string                   # Required: Add-on name
  version           = optional(string)         # Optional: Specific version or omit for latest
  resolve_conflicts = optional(string, "OVERWRITE")  # OVERWRITE, PRESERVE, or NONE
}
```

## Outputs

This module currently does not export outputs. Add-on status can be checked via AWS CLI or Console.

## Conflict Resolution Strategies

| Strategy | Behavior |
|----------|----------|
| `OVERWRITE` | AWS overwrites custom configurations (recommended) |
| `PRESERVE` | Keeps existing custom configurations |
| `NONE` | Fails if conflicts exist |

**Recommendation**: Use `OVERWRITE` for most cases to ensure AWS-managed configuration.

## Checking Add-on Versions

```bash
# List available add-on versions
aws eks describe-addon-versions --addon-name eks-pod-identity-agent

# Check currently installed add-ons
aws eks list-addons --cluster-name eks-cluster-dev

# Get add-on details
aws eks describe-addon --cluster-name eks-cluster-dev --addon-name eks-pod-identity-agent
```

## Verification

```bash
# Check add-on status in cluster
kubectl get daemonset -n kube-system
kubectl get deployment -n kube-system

# Specifically for eks-pod-identity-agent
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent

# Check add-on health in AWS
aws eks describe-addon \
  --cluster-name eks-cluster-dev \
  --addon-name eks-pod-identity-agent \
  --query 'addon.health'
```

## Common Add-on Combinations

### Minimal (Default)
```hcl
addon_list = [
  { name = "vpc-cni" },
  { name = "coredns" },
  { name = "kube-proxy" }
]
```

### With Pod Identity Support
```hcl
addon_list = [
  { name = "vpc-cni" },
  { name = "coredns" },
  { name = "kube-proxy" },
  { name = "eks-pod-identity-agent" }  # Enables Pod Identity for EBS CSI
]
```

### Full Stack
```hcl
addon_list = [
  { name = "vpc-cni" },
  { name = "coredns" },
  { name = "kube-proxy" },
  { name = "eks-pod-identity-agent" },
  { name = "aws-ebs-csi-driver" },
  { name = "snapshot-controller" }
]
```

## Troubleshooting

### Add-on stuck in "Degraded" state
```bash
aws eks describe-addon \
  --cluster-name eks-cluster-dev \
  --addon-name <addon-name> \
  --query 'addon.health.issues'
```

**Common causes:**
- Incompatible version with EKS cluster version
- Insufficient node resources
- IAM role issues (for add-ons requiring Pod Identity/IRSA)

### Upgrade fails
Set `resolve_conflicts = "OVERWRITE"` to allow AWS to override custom configurations.

### Check add-on logs
```bash
# For eks-pod-identity-agent
kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

## Best Practices

1. **Pin versions in production**: Avoid auto-updates
2. **Use OVERWRITE for conflicts**: Let AWS manage configuration
3. **Install pod-identity-agent first**: Before deploying Pod Identity workloads
4. **Test in dev**: Verify add-on versions before promoting to prod
5. **Monitor health**: Use `describe-addon` to check status

## Notes

- Add-ons are installed via AWS EKS API, not Helm
- Some add-ons (like EBS CSI Driver) can also be installed via Helm for more control
- This module focuses on the `eks-pod-identity-agent` required for Pod Identity feature
- Default add-ons (vpc-cni, coredns, kube-proxy) are usually pre-installed by EKS
