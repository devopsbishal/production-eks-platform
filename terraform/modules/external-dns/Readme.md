# External DNS Module

This module deploys External DNS to automatically manage Route53 DNS records based on Kubernetes Ingress and Service resources.

## Purpose

External DNS watches for Kubernetes Ingress/Service resources with specific annotations and automatically creates/updates/deletes corresponding DNS records in Route53.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                           │
│                                                                  │
│  ┌─────────────────┐     ┌──────────────────┐                   │
│  │ Ingress         │     │ External DNS Pod │                   │
│  │ annotations:    │────▶│                  │                   │
│  │   external-dns/ │     │ ServiceAccount   │                   │
│  │   hostname      │     │ with IRSA        │                   │
│  └─────────────────┘     └────────┬─────────┘                   │
│                                   │                              │
└───────────────────────────────────┼──────────────────────────────┘
                                    │ AssumeRoleWithWebIdentity
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AWS IAM                                  │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ IAM Role: eks-cluster-dev-external-dns-role             │    │
│  │ Trust: EKS OIDC Provider                                │    │
│  │ Policy: route53:ChangeResourceRecordSets, etc.          │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Route53 Hosted Zone                         │
│                                                                  │
│  A     app.eks.example.com    →  ALB IP                         │
│  TXT   external-dns-app...    →  "heritage=external-dns..."     │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **IRSA Authentication**: Secure AWS API access without static credentials
- **Sync Policy**: Creates, updates, and deletes DNS records automatically
- **TXT Ownership Records**: Prevents conflicts between multiple clusters
- **Domain Filtering**: Only manages records for specified domains

## Usage

```hcl
module "external_dns" {
  source = "../../modules/external-dns"

  eks_cluster_name  = module.eks.cluster_name
  aws_region        = "us-west-2"
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn
  domain_name       = "eks.example.com"
  environment       = "dev"

  depends_on = [module.eks, module.route53_zone]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `eks_cluster_name` | Name of the EKS cluster | `string` | n/a | yes |
| `aws_region` | AWS region | `string` | n/a | yes |
| `oidc_provider` | EKS OIDC provider URL (without https://) | `string` | n/a | yes |
| `oidc_provider_arn` | ARN of the OIDC provider | `string` | n/a | yes |
| `domain_name` | Domain to manage DNS records for | `string` | n/a | yes |
| `environment` | Environment name | `string` | `"dev"` | no |
| `namespace` | Kubernetes namespace for External DNS | `string` | `"kube-system"` | no |
| `policy` | DNS policy: sync, upsert-only, or create-only | `string` | `"sync"` | no |
| `helm_chart_version` | External DNS Helm chart version | `string` | `"1.18.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `iam_role_arn` | ARN of the IAM role |
| `iam_role_name` | Name of the IAM role |
| `namespace` | Kubernetes namespace |
| `service_account_name` | ServiceAccount name |

## Creating DNS Records

Add the `external-dns.alpha.kubernetes.io/hostname` annotation to your Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    external-dns.alpha.kubernetes.io/hostname: app.eks.example.com
    external-dns.alpha.kubernetes.io/ttl: "300"
spec:
  ingressClassName: alb
  rules:
    - host: app.eks.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

## Verification

```bash
# Check External DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns

# Verify DNS record in Route53
aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>

# Test DNS resolution
dig app.eks.example.com
```

## Policy Options

| Policy | Creates | Updates | Deletes | Use Case |
|--------|---------|---------|---------|----------|
| `sync` | ✅ | ✅ | ✅ | Full lifecycle management |
| `upsert-only` | ✅ | ✅ | ❌ | Safer for production (no deletions) |
| `create-only` | ✅ | ❌ | ❌ | Initial setup only, manual changes preserved |

- **sync**: Full control - creates, updates, and deletes records
- **upsert-only**: Creates and updates but never deletes (recommended for production)
- **create-only**: Only creates new records, never modifies or deletes existing ones

## IAM Permissions

The module creates an IAM policy with these permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:ChangeResourceRecordSets",
    "route53:ListResourceRecordSets",
    "route53:ListTagsForResources"
  ],
  "Resource": ["arn:aws:route53:::hostedzone/*"]
},
{
  "Effect": "Allow",
  "Action": ["route53:ListHostedZones"],
  "Resource": ["*"]
}
```
