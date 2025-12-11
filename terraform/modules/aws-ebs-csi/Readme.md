# AWS EBS CSI Driver Module

This module deploys the AWS EBS CSI Driver to enable dynamic provisioning of Amazon EBS volumes as Kubernetes persistent volumes.

## Purpose

The EBS CSI Driver allows Kubernetes pods to use Amazon EBS volumes for persistent storage. It supports dynamic volume provisioning, volume snapshots, and volume resizing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                           │
│                                                                  │
│  ┌─────────────────┐     ┌──────────────────────────┐           │
│  │ Pod with PVC    │     │ EBS CSI Controller Pod   │           │
│  │                 │────▶│                          │           │
│  │ /data (mount)   │     │ ServiceAccount:          │           │
│  │                 │     │ ebs-csi-controller-sa    │           │
│  └─────────────────┘     └────────┬─────────────────┘           │
│                                   │                              │
└───────────────────────────────────┼──────────────────────────────┘
                                    │ Pod Identity
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AWS IAM                                  │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ IAM Role: eks-cluster-dev-ebs-csi-role                  │    │
│  │ Trust: pods.eks.amazonaws.com                           │    │
│  │ Policy: AmazonEBSCSIDriverPolicy (AWS Managed)          │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Amazon EBS                                  │
│                                                                  │
│  gp3 Volume (10GB)  →  Attached to Node  →  Mounted to Pod     │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **Dynamic Provisioning**: Automatically creates EBS volumes when PVCs are created
- **Volume Snapshots**: Supports creating snapshots for backup/restore
- **Volume Resizing**: Expand volumes without recreating pods
- **Pod Identity Authentication**: Uses modern Pod Identity instead of IRSA
- **gp3 Support**: Latest generation EBS volumes with better performance/cost

## Pod Identity vs IRSA

This module uses **EKS Pod Identity** (not IRSA) for AWS API access:

| Aspect | IRSA (ALB/External DNS) | Pod Identity (EBS CSI) |
|--------|-------------------------|------------------------|
| Trust Principal | OIDC Provider | `pods.eks.amazonaws.com` |
| Requires | OIDC provider setup | `eks-pod-identity-agent` addon |
| Association | ServiceAccount annotation | `aws_eks_pod_identity_association` |
| Status | Established (2019+) | Newer (2023+) |

**Why Pod Identity for EBS CSI?**
- Simpler setup (no OIDC provider needed beyond EKS)
- Native EKS integration
- AWS-managed policy already exists
- Recommended by AWS for newer workloads

## Prerequisites

- EKS cluster version 1.24+
- `eks-pod-identity-agent` addon installed (handled by `eks-addons` module)

## Usage

```hcl
module "aws_ebs_csi" {
  source = "../../modules/aws-ebs-csi"

  cluster_name       = module.eks.cluster_name
  helm_chart_version = "2.52.1"
  environment        = "dev"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | Name of the EKS cluster | `string` | n/a | yes |
| `helm_chart_version` | EBS CSI Driver Helm chart version | `string` | `"2.52.1"` | no |
| `namespace` | Kubernetes namespace for deployment | `string` | `"kube-system"` | no |
| `service_account_name` | ServiceAccount name | `string` | `"ebs-csi-controller-sa"` | no |
| `environment` | Environment name | `string` | `"dev"` | no |
| `resource_tag` | Common tags for resources | `map(string)` | `{}` | no |

## Outputs

This module currently does not export outputs. IAM role ARN can be added if needed.

## Creating Persistent Volumes

### StorageClass (gp3)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3-sc
  resources:
    requests:
      storage: 10Gi
```

### Pod Using the PVC

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

## Verification

```bash
# Check EBS CSI controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check Pod Identity association
aws eks list-pod-identity-associations --cluster-name eks-cluster-dev

# Create test PVC and verify volume creation
kubectl apply -f test-manifest/ebs-csi-test.yaml
kubectl get pvc
kubectl get pv

# Check EBS volume in AWS
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/eks-cluster-dev,Values=owned"
```

## Volume Parameters

| Type | IOPS | Throughput | Use Case | Cost |
|------|------|------------|----------|------|
| `gp3` | 3000-16000 | 125-1000 MB/s | General purpose | Lowest |
| `io2` | Up to 64000 | High | Database, high IOPS | Higher |
| `st1` | - | 500 MB/s | Big data, logs | Lower |

## Troubleshooting

### PVC stuck in Pending
```bash
kubectl describe pvc <pvc-name>
# Check: "Events" section for errors
```

**Common causes:**
- Pod Identity not configured
- IAM role missing permissions
- No available nodes in the AZ

### Volume fails to attach
```bash
kubectl describe pod <pod-name>
# Look for "FailedAttachVolume" or "FailedMount"
```

**Solution**: Check node has capacity and IAM role is correct.

## IAM Permissions

Uses AWS Managed Policy: `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy`

Key permissions:
- `ec2:CreateVolume`
- `ec2:AttachVolume`
- `ec2:DeleteVolume`
- `ec2:CreateSnapshot`
- `ec2:DeleteSnapshot`
