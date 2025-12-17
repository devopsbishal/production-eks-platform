# ArgoCD Module

This module deploys ArgoCD to an EKS cluster using Helm, providing a GitOps continuous delivery platform for Kubernetes.

## Features

- **High Availability**: Multiple replicas for server, controller, repo-server, and ApplicationSet
- **Redis HA**: Redis high availability for production resilience
- **Insecure Mode**: TLS terminated at ALB (not at pod level)
- **Exec Enabled**: Allows kubectl exec into pods for debugging
- **ClusterIP Service**: Works with external ALB Ingress

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD GitOps Flow                            │
└─────────────────────────────────────────────────────────────────┘

   ┌─────────────┐      ┌─────────────┐      ┌─────────────────┐
   │   Git Repo  │ ──── │   ArgoCD    │ ──── │   Kubernetes    │
   │  (Source)   │      │ Controller  │      │   Cluster       │
   └─────────────┘      └─────────────┘      └─────────────────┘
         │                    │                      │
    Push changes         Detect drift           Apply changes
    to manifests         & sync                 to cluster
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD Namespace (argocd)                     │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  argocd-server  │  │   controller    │  │   repo-server   │ │
│  │  (2 replicas)   │  │  (2 replicas)   │  │  (2 replicas)   │ │
│  │  - Web UI       │  │  - Git sync     │  │  - Git clone    │ │
│  │  - API          │  │  - K8s apply    │  │  - Manifest gen │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │  applicationset │  │   redis-ha      │                       │
│  │  (2 replicas)   │  │  (3 replicas)   │                       │
│  │  - App gen      │  │  - Cache/state  │                       │
│  └─────────────────┘  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Basic Usage

```hcl
module "argocd" {
  source = "../../modules/argocd"

  depends_on = [module.aws_load_balancer_controller]
}
```

### With Custom Helm Chart Version

```hcl
module "argocd" {
  source = "../../modules/argocd"

  helm_chart_version = "7.0.0"
  namespace          = "argocd"

  depends_on = [module.aws_load_balancer_controller]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| helm | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| helm | >= 2.0 |

## Resources

| Name | Type |
|------|------|
| helm_release.argocd | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| helm_chart_version | Version of the ArgoCD Helm chart | `string` | `"9.1.7"` | no |
| namespace | Kubernetes namespace to deploy ArgoCD | `string` | `"argocd"` | no |
| service_account_name | Name of the service account | `string` | `"argocd"` | no |
| argocd_hostname | Hostname for ArgoCD web UI (optional) | `string` | `""` | no |

## Outputs

This module does not export outputs. Use kubectl to interact with ArgoCD.

## Post-Installation

### Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Login via CLI

```bash
# Install ArgoCD CLI (macOS)
brew install argocd

# Login
argocd login argocd.eks.example.com --username admin --password <password>
```

### Create Ingress for Web UI

Create an Ingress to expose ArgoCD externally:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:ACCOUNT:certificate/CERT-ID
    external-dns.alpha.kubernetes.io/hostname: argocd.eks.example.com
spec:
  ingressClassName: alb
  rules:
    - host: argocd.eks.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```

## IAM Requirements

**ArgoCD does NOT require AWS IAM roles** for standard operation.

ArgoCD communicates with:
- ✅ Git repositories (GitHub/GitLab) - uses SSH key or token
- ✅ Kubernetes API - uses ServiceAccount (K8s RBAC)
- ✅ Helm repositories - public or authenticated with basic auth

ArgoCD does NOT communicate with:
- ❌ AWS EC2 API
- ❌ AWS EBS API
- ❌ AWS S3 (unless storing Helm charts)
- ❌ AWS Secrets Manager (use external-secrets-operator for that)

## HA Configuration Details

| Component | Replicas | Purpose |
|-----------|----------|---------|
| argocd-server | 2 | Web UI and API server |
| argocd-application-controller | 2 | Git sync and K8s reconciliation |
| argocd-repo-server | 2 | Git clone and manifest generation |
| argocd-applicationset-controller | 2 | ApplicationSet templating |
| redis-ha | 3 | Distributed cache and state |

## GitOps Workflow

### 1. Create Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 2. App of Apps Pattern (Recommended)

```yaml
# Root application that manages other applications
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo.git
    path: bootstrap
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n argocd

# Check events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Cannot Login

1. Verify the argocd-server pods are running
2. Check the initial admin secret exists
3. Ensure ingress is correctly configured

```bash
# Reset admin password
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'$(htpasswd -bnBC 10 "" newpassword | tr -d ':\n')'"}}'
```

### Sync Failed

```bash
# Check application status
argocd app get my-app

# Check sync details
argocd app sync my-app --dry-run
```

## Best Practices

1. **Use App of Apps Pattern**: Manage all applications from a single root application
2. **Enable Auto-Sync**: Let ArgoCD automatically apply changes from Git
3. **Use ApplicationSets**: For multi-cluster or multi-environment deployments
4. **Separate Repos**: Keep GitOps manifests in a separate repo from application code
5. **RBAC**: Configure ArgoCD RBAC for team-based access control
6. **Notifications**: Set up Slack/email notifications for sync status

## Related Modules

- [acm](../acm/) - SSL certificate for HTTPS access
- [aws-load-balancer-controller](../aws-load-balancer-controller/) - ALB for ingress
- [external-dns](../external-dns/) - Automatic DNS record management
