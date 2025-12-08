# AWS Load Balancer Controller Module

This module deploys the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) on an EKS cluster using Helm and configures IAM Roles for Service Accounts (IRSA) for secure AWS API access.

## 📋 Table of Contents
- [Overview](#-overview)
- [Architecture](#️-architecture)
- [Prerequisites](#-prerequisites)
- [Usage](#-usage)
- [Inputs](#-inputs)
- [Outputs](#-outputs)
- [How It Works](#-how-it-works)
- [Testing](#-testing)
- [Troubleshooting](#-troubleshooting)

## 🎯 Overview

The AWS Load Balancer Controller is a Kubernetes controller that manages AWS Elastic Load Balancers for Kubernetes clusters. It provisions:
- **Application Load Balancers (ALB)** for Kubernetes Ingress resources
- **Network Load Balancers (NLB)** for Kubernetes Service resources of type LoadBalancer

### Key Features
- ✅ IRSA (IAM Roles for Service Accounts) for secure AWS access
- ✅ Helm-based deployment via Terraform
- ✅ Configurable replica count for high availability
- ✅ IP target type for direct pod traffic (VPC CNI)
- ✅ Automatic ALB/NLB provisioning from K8s resources

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         EKS Cluster                                  │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    kube-system namespace                        │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │         AWS Load Balancer Controller (2 replicas)         │  │ │
│  │  │                                                            │  │ │
│  │  │  ┌─────────────────┐    ┌─────────────────┐              │  │ │
│  │  │  │   Controller    │    │   Controller    │              │  │ │
│  │  │  │   (leader)      │    │   (standby)     │              │  │ │
│  │  │  └────────┬────────┘    └─────────────────┘              │  │ │
│  │  │           │                                                │  │ │
│  │  │           │ IRSA (ServiceAccount)                         │  │ │
│  │  │           │ ↓                                              │  │ │
│  │  │  ┌────────┴────────┐                                      │  │ │
│  │  │  │  IAM Role ARN   │ ────→ AWS API (sts:AssumeRoleWithWebIdentity)
│  │  │  └─────────────────┘                                      │  │ │
│  │  └──────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           AWS Services                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐ │
│  │  Application    │  │    Network      │  │   Target Groups     │ │
│  │  Load Balancer  │  │  Load Balancer  │  │   (IP Target Type)  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### IRSA Flow
```
K8s ServiceAccount ──→ OIDC Provider ──→ IAM Role ──→ AWS Permissions
     (annotated)         (trust)         (policy)     (ALB/NLB/EC2/etc.)
```

## 📦 Prerequisites

Before using this module, ensure:

1. **EKS Cluster with OIDC Provider**
   ```hcl
   # Your EKS module must output:
   output "oidc_provider_arn" { ... }
   output "oidc_provider" { ... }
   ```

2. **Helm Provider Configured**
   ```hcl
   provider "helm" {
     kubernetes {
       host                   = data.aws_eks_cluster.cluster.endpoint
       cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
       token                  = data.aws_eks_cluster_auth.cluster.token
     }
   }
   ```

3. **VPC Subnets Tagged for ALB Discovery**
   ```hcl
   # Public subnets (internet-facing ALB)
   "kubernetes.io/role/elb" = "1"
   
   # Private subnets (internal ALB)
   "kubernetes.io/role/internal-elb" = "1"
   
   # Cluster tag
   "kubernetes.io/cluster/<cluster-name>" = "shared"
   ```

## 🚀 Usage

### Basic Usage
```hcl
module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  eks_cluster_name  = module.eks.cluster_name
  vpc_id            = module.vpc.vpc_id
  aws_region        = "us-west-2"
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn
  environment       = "dev"
}
```

### Production Usage (with custom settings)
```hcl
module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  eks_cluster_name   = module.eks.cluster_name
  vpc_id             = module.vpc.vpc_id
  aws_region         = "us-west-2"
  oidc_provider      = module.eks.oidc_provider
  oidc_provider_arn  = module.eks.oidc_provider_arn
  environment        = "prod"
  helm_chart_version = "1.11.0"
  replicas           = 3  # More replicas for HA
}
```

## 📥 Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `eks_cluster_name` | Name of the EKS cluster | `string` | - | ✅ |
| `vpc_id` | VPC ID where EKS is deployed | `string` | - | ✅ |
| `aws_region` | AWS region | `string` | - | ✅ |
| `oidc_provider` | OIDC provider URL (without https://) | `string` | - | ✅ |
| `oidc_provider_arn` | ARN of the OIDC provider | `string` | - | ✅ |
| `environment` | Environment name (dev/staging/prod) | `string` | `"dev"` | ❌ |
| `helm_chart_version` | Helm chart version | `string` | `"1.11.0"` | ❌ |
| `replicas` | Number of controller replicas | `number` | `2` | ❌ |
| `resource_tag` | Common tags for resources | `map(string)` | See variables.tf | ❌ |

## 📤 Outputs

| Name | Description |
|------|-------------|
| `iam_role_arn` | ARN of the IAM role for the controller |
| `iam_policy_arn` | ARN of the IAM policy attached to the role |

## 🔧 How It Works

### 1. IAM Policy
Downloads and uses the official AWS-provided IAM policy that grants permissions to:
- Create/delete ALBs and NLBs
- Manage Target Groups
- Modify Security Groups
- Read EC2, VPC, and ACM resources

**Policy Source**: `policies/iam-policy.json`
> Source: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

### 2. IAM Role with OIDC Trust
Creates an IAM role that can be assumed by the Kubernetes ServiceAccount via IRSA:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "<OIDC_PROVIDER_ARN>"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "<OIDC_PROVIDER>:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
    }
  }
}
```

### 3. Helm Release
Deploys the controller with:
- ServiceAccount annotated with IAM role ARN
- IP target type (direct pod traffic)
- Cluster name and VPC ID for resource discovery

## 🧪 Testing

After deployment, test with a sample Ingress:

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
---
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
spec:
  type: ClusterIP
  selector:
    app: nginx-test
  ports:
    - port: 80
      targetPort: 80
---
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-test
                port:
                  number: 80
```

**Apply and verify**:
```bash
kubectl apply -f deployment.yaml -f service.yaml -f ingress.yaml

# Wait for ALB provisioning (~2-3 minutes)
kubectl get ingress nginx-test -w

# Get ALB URL
kubectl get ingress nginx-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 🔍 Troubleshooting

### Controller Pods Not Starting
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Ingress Not Creating ALB
```bash
kubectl describe ingress <ingress-name>
```

**Common causes**:
1. **Missing subnet tags** - Ensure subnets have `kubernetes.io/role/elb` or `kubernetes.io/role/internal-elb`
2. **Wrong cluster tag** - Subnets must have `kubernetes.io/cluster/<cluster-name> = shared`
3. **IRSA not working** - Check IAM role trust policy and ServiceAccount annotation

### Subnet Discovery Error
```
couldn't auto-discover subnets: unable to resolve at least one subnet
```

**Fix**: Add proper tags to your subnets:
```hcl
# For public subnets (internet-facing ALB)
tags = {
  "kubernetes.io/role/elb"                      = "1"
  "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
}

# For private subnets (internal ALB)
tags = {
  "kubernetes.io/role/internal-elb"             = "1"
  "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
}
```

### IRSA Not Working
```bash
# Check ServiceAccount annotation
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml

# Verify it has:
# annotations:
#   eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/ROLE_NAME
```

## 📚 Resources

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS Charts Helm Repository](https://github.com/aws/eks-charts)
- [Ingress Annotations Reference](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [NLB Annotations Reference](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)

---

**Last Updated**: December 8, 2025
