# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2025-12-18] - GitOps Sample Application Deployment

### Added
- **GitOps Repository Structure** (`gitops-apps/`)
  - Sample nginx application manifests
  - ArgoCD Application CRD for GitOps workflow
  - Demonstration of complete GitOps lifecycle

- **Sample Application** (`gitops-apps/apps/sample-app/`)
  - Nginx deployment (3 replicas with HA)
  - ClusterIP service
  - ALB ingress with HTTPS and External DNS integration
  - Resource requests for autoscaling compatibility
  - Tier labels for organization (frontend tier)

- **ArgoCD Application Manifest** (`gitops-apps/argocd-apps/sample-app.yaml`)
  - Application CRD pointing to Git repository
  - Automated sync policy with prune and self-heal enabled
  - Auto-create namespace feature
  - Finalizers for cascade deletion

### Technical Implementation
- **GitOps Workflow**: Git → ArgoCD (3-min sync) → Cluster
- **Repository**: https://github.com/devopsbishal/production-eks-platform.git
- **Auto-Sync**: Enabled with prune and self-heal
- **Sample App**: nginx:1.29.4, 3 replicas, HTTPS with wildcard ACM cert
- **Access**: https://sample-app.eks.rentalhubnepal.com

### Key Learnings

1. **GitOps in Action**: Demonstrated complete GitOps workflow
   - Commit to Git → ArgoCD detects change → Auto-sync to cluster
   - Self-heal prevents configuration drift
   - Tested by changing replica count (3→5) in Git

2. **ArgoCD Sync Intervals**: Default 3-minute polling
   - Can force immediate sync via UI or annotation
   - Configurable via `timeout.reconciliation` in argocd-cm ConfigMap

3. **Resource Deletion with ArgoCD**:
   - Direct kubectl delete triggers self-heal (recreates resource)
   - Proper way: Delete ArgoCD Application CRD (cascades to all resources)
   - Alternative: Remove manifests from Git (prune deletes resources)

4. **DNS Propagation Behavior**:
   - Route53 records created instantly by External DNS
   - DNS cache issues on client side (not AWS)
   - Google DNS (8.8.8.8) had ~10 minute sync delay
   - Cloudflare DNS (1.1.1.1) synced within 2 minutes
   - Solution: Use multiple DNS providers for redundancy

5. **Wildcard Certificate Reuse**:
   - Single ACM wildcard cert (`*.eks.rentalhubnepal.com`) covers all services
   - Same certificate ARN used for ArgoCD and sample-app ingresses

### Verification Commands
```bash
# Check ArgoCD Application status
kubectl get application -n argocd sample-app

# Check deployed resources
kubectl get all -n sample-app

# Test HTTPS endpoint
curl -I https://sample-app.eks.rentalhubnepal.com
```

### Consequences
- GitOps workflow fully operational (Git → ArgoCD → Cluster)
- Zero-touch deployments demonstrated
- Self-heal ensures cluster matches Git state

---

## [2025-12-17] - ArgoCD & ACM Certificate

### Added
- **ArgoCD Module** (`terraform/modules/argocd/`)
  - GitOps continuous delivery platform for Kubernetes
  - High Availability setup with 2 replicas per component
  - Redis HA enabled for production resilience
  - Insecure mode (TLS terminated at ALB, not pod)
  - ClusterIP service for external ALB ingress
  - Exec enabled for debugging

- **Access Configuration**:
  - Ingress created separately (not via Helm) for flexibility
  - TLS terminated at ALB using ACM certificate
  - Initial admin password in Kubernetes secret

- **IAM**: No AWS IAM role required (ArgoCD only talks to Git and K8s API)

#### ACM Certificate
- **Validation Method**: DNS (automatic via Route53)
- **Domain Configuration**:
  - Primary: `*.eks.example.com` (wildcard)
  - SAN: `eks.example.com` (base domain)

- **Deduplication Fix**: Wildcard and base domain share same validation CNAME
  - Used `tolist()[0]` to create single validation record
  - `allow_overwrite = true` for idempotency

### Key Decisions
- **Ingress Outside Helm**: Created ingress via kubectl manifest instead of Helm for better control and GitOps compatibility
- **No IAM for ArgoCD**: ArgoCD doesn't need AWS access, simplifies setup
- **Wildcard Certificate**: Single cert covers all subdomains, reduces management overhead

### Documentation
- README for acm module (comprehensive)
- README for argocd module (comprehensive with GitOps examples)

---

## [2025-12-14] - Cluster Autoscaler & Karpenter

### Added
- **EKS Node Group Module** (`terraform/modules/eks-node-group/`)
  - Reusable module for creating EKS managed node groups
  - Support for SPOT and On-Demand capacity types
  - Multiple instance types per node group for SPOT availability
  - Configurable scaling (min, max, desired size)
  - Automatic EKS cluster joining (no bootstrap script required)
  - Scale-from-zero capability (min_size=0, desired_size=0)
  - Update configuration for rolling updates

- **Cluster Autoscaler Module** (`terraform/modules/cluster-autoscaler/`)
  - Kubernetes Cluster Autoscaler for managed node groups
  - **Pod Identity** authentication (not IRSA)
  - Custom IAM policy with scoped permissions
  - Helm release (version 9.53.0)
  - Automatically scales node groups based on pod demands
  - Scale-down of underutilized nodes after 10 minutes
  - Support for multiple node groups with different instance types

- **Karpenter Module** (`terraform/modules/karpenter/`)
  - Modern node autoscaler with faster provisioning (30-60s vs 2-4min)
  - Uses official `terraform-aws-modules/eks/aws//modules/karpenter` v20.31
  - **Pod Identity** authentication via module
  - Dynamic instance type selection based on workload requirements
  - SQS queue for SPOT interruption handling
  - EventBridge rules for instance lifecycle events
  - Automatic consolidation and cost optimization
  - Karpenter v1.0.0 with v1 API permissions
  - Helm chart deployment (version 1.0.0)

- **VPC Discovery Tags**
  - Added `karpenter.sh/discovery` tag to all subnets
  - Added `karpenter.sh/discovery` tag to EKS cluster security group
  - Enables Karpenter to discover VPC resources automatically

- **Node Groups in Dev Environment**
  - `node_group_general`: t3.medium/large SPOT instances
    - min=2, max=5, desired=3 (always-on HA nodes)
    - For general workloads and system pods
  - `node_group_compute`: c5.xlarge/2xlarge SPOT instances
    - min=0, max=5, desired=0 (scale-from-zero)
    - For compute-intensive batch workloads

- **Test Manifests**
  - `autoscaler-test.yaml` - Stress deployment for testing Cluster Autoscaler
  - `NodePoll.yaml` - Karpenter NodePool and EC2NodeClass CRDs

- **Documentation**
  - README for eks-node-group module
  - README for cluster-autoscaler module (comprehensive)
  - README for karpenter module (comprehensive)

### Technical Implementation

#### Cluster Autoscaler
- **Authentication**: Pod Identity (not IRSA)
  - IAM role: `ClusterAutoscaler-${cluster_name}`
  - Trust principal: `pods.eks.amazonaws.com`
  - Pod Identity association via `aws_eks_pod_identity_association`

- **Node Group Tagging**: Required for discovery
  ```hcl
  tags = {
    "k8s.io/cluster-autoscaler/enabled"         = "true"
    "k8s.io/cluster-autoscaler/${cluster_name}" = "owned"
  }
  ```

- **Helm Configuration**:
  - Namespace: `kube-system`
  - ServiceAccount: `cluster-autoscaler`
  - Replica: 1 (single controller)
  - Fixed path: `rbac.serviceAccount.*` (not `controller.serviceAccount.*`)

#### Karpenter
- **AWS Resources** (created by terraform-aws-modules):
  - Controller IAM role with Karpenter policy
  - Node IAM role: `KarpenterNodeRole-${cluster_name}`
  - Instance profile for EC2 nodes
  - SQS queue for interruption notifications
  - EventBridge rules: SPOT interruption, rebalance, state change, health events
  - Access entry for nodes to join cluster

- **Pod Identity Configuration**:
  - `enable_irsa = false`
  - `create_pod_identity_association = true`
  - Namespace: `karpenter`
  - ServiceAccount: `karpenter`

- **Helm Configuration**:
  - Uses modern `set = []` array syntax (not `set {}` blocks)
  - Settings: clusterName, clusterEndpoint, interruptionQueue
  - Resource limits: 1 CPU, 1Gi memory

- **NodePool & EC2NodeClass**:
  - AMI selector: `al2023` (Amazon Linux 2023)
  - Capacity type: SPOT instances
  - Instance categories: c, m, r (compute, general, memory-optimized)
  - Instance generation: >2 (generation 3 and above)
  - Subnet/SG discovery via `karpenter.sh/discovery` tags
  - Consolidation: WhenEmptyOrUnderutilized after 1m

### Key Decisions

1. **Separate Node Group Module**: Created dedicated `eks-node-group` module
   - Reusable across environments
   - Separated from eks module for better modularity
   - Managed node groups vs self-managed (easier to maintain)

2. **Pod Identity for Both Autoscalers**: Consistent authentication pattern
   - Simpler than IRSA (no ServiceAccount annotations needed)
   - Modern AWS recommendation
   - Requires `eks-pod-identity-agent` addon

3. **Multiple Instance Types per Node Group**: SPOT availability
   - t3.medium + t3.large (general node group)
   - c5.xlarge + c5.2xlarge (compute node group)
   - Reduces SPOT interruption probability
   - AWS can fallback to alternative instance types

4. **Scale-from-Zero Pattern**: Cost optimization
   - Compute node group starts at 0 nodes
   - Scales up when workloads require capacity
   - Saves costs when idle
   - Acceptable 2-4 minute startup delay for batch workloads

5. **Both Cluster Autoscaler AND Karpenter**: Learning both approaches
   - Cluster Autoscaler: Traditional, ASG-based, 2-4min provisioning
   - Karpenter: Modern, dynamic instance selection, 30-60s provisioning
   - Can coexist for gradual migration
   - Karpenter is the future direction

6. **Official Karpenter Module**: Used terraform-aws-modules
   - Simpler than custom implementation
   - Handles all AWS resources (IAM, SQS, EventBridge)
   - Actively maintained
   - Community best practices

7. **VPC Discovery Tags**: Centralized resource discovery
   - Added in VPC module (subnets)
   - Added in EKS module (security group)
   - Consistent pattern: `karpenter.sh/discovery = cluster_name`
   - Karpenter finds resources automatically

### Configuration Patterns

**Node Group Tagging Strategy**:
```hcl
# General node group (Cluster Autoscaler)
tags = {
  "k8s.io/cluster-autoscaler/enabled"           = "true"
  "k8s.io/cluster-autoscaler/eks-cluster-dev"   = "owned"
}

# VPC resources (Karpenter)
tags = {
  "karpenter.sh/discovery" = "eks-cluster-dev"
}
```

**Capacity Type Strategy**:
- General workloads: SPOT (60-90% cost savings)
- Critical workloads: Use On-Demand node group (not implemented yet)
- SPOT acceptable for dev/staging environments

**Scaling Behavior**:
- Cluster Autoscaler: Reactive, ~2-4 minutes
- Karpenter: Proactive, ~30-60 seconds
- Scale down: 10 minutes (Cluster Autoscaler) vs 1 minute (Karpenter)

### Troubleshooting Solutions

1. **Cluster Autoscaler Helm Paths**: Fixed incorrect ServiceAccount paths
   - Correct: `rbac.serviceAccount.create`, `rbac.serviceAccount.name`
   - Incorrect: `controller.serviceAccount.*`

2. **Karpenter AMI Resolution**: Fixed invalid AMI alias
   - Invalid: `al2023@${ALIAS_VERSION}` (literal string)
   - Valid: `al2023` or `al2023@latest`

3. **Karpenter Resource Discovery**: Added missing VPC tags
   - Subnets: `karpenter.sh/discovery = cluster_name`
   - Security Groups: `karpenter.sh/discovery = cluster_name`
   - Without tags: SubnetsNotFound, SecurityGroupsNotFound errors

4. **Stuck EC2NodeClass Deletion**: Removed finalizers
   - Finalizer: `karpenter.k8s.aws/termination`
   - Manual patch: `kubectl patch ec2nodeclass <name> -p '{"metadata":{"finalizers":null}}' --type=merge`

---

## [2025-12-11] - EKS Add-ons & EBS CSI Driver

### Added
- **EKS Add-ons Module** (`terraform/modules/eks-addons/`)
  - Manages native EKS add-ons via AWS EKS Add-on API
  - Installed `eks-pod-identity-agent` addon for Pod Identity feature
  - Supports version pinning and conflict resolution strategies
  - Dynamic add-on list with `for_each` pattern

- **AWS EBS CSI Driver Module** (`terraform/modules/aws-ebs-csi/`)
  - Deployed via Helm chart (version 2.52.1)
  - Uses **Pod Identity** authentication (not IRSA)
  - IAM role with AWS managed policy `AmazonEBSCSIDriverPolicy`
  - Pod Identity association for ServiceAccount
  - Enables dynamic EBS volume provisioning for StatefulSets

- **Test Manifests**
  - `ebs-csi-test.yaml` - StorageClass (gp3), PVC, and test pod
  - Verified dynamic volume provisioning works

- **Documentation**
  - README for eks-addons module
  - README for aws-ebs-csi module

### Technical Implementation
- **Pod Identity vs IRSA**: EBS CSI uses newer Pod Identity method
  - Trust principal: `pods.eks.amazonaws.com`
  - Association: `aws_eks_pod_identity_association` resource
  - Simpler than IRSA (no OIDC provider annotations needed)
  - Requires `eks-pod-identity-agent` addon

- **Dynamic Add-on Management**: Converted list to map using addon name as key
  ```hcl
  for_each = { for addon in var.addon_list : addon.name => addon }
  ```

### Key Decisions
- Chose Pod Identity over IRSA for EBS CSI (modern AWS recommendation)
- Used AWS managed policy instead of custom IAM policy
- Installed eks-pod-identity-agent as EKS addon (not Helm)

---

## [2025-12-09] - External DNS & Route53 Zone

### Added
- **Route53 Zone Module** (`terraform/modules/route53-zone/`)
  - Creates Route53 hosted zone for subdomain delegation
  - Outputs name servers for configuring primary DNS provider
  - Supports tagging and environment variables
  - Designed for Cloudflare → Route53 subdomain delegation pattern

- **External DNS Module** (`terraform/modules/external-dns/`)
  - IRSA setup for secure Route53 API access
  - IAM policy with minimal Route53 permissions
  - Helm release with AWS provider configuration
  - Domain filtering to limit managed records
  - TXT ownership records to prevent multi-cluster conflicts
  - Configurable policy (sync vs upsert-only)

- **Test Manifests**
  - `ingress-external-dns.yaml` - Ingress with External DNS annotations

- **Documentation**
  - README for route53-zone module
  - README for external-dns module

### Configuration
- Subdomain: `eks.rentalhubnepal.com` delegated from Cloudflare to Route53
- External DNS watches Ingress and Service resources
- TXT prefix: `external-dns-` for ownership tracking

### Integration
- Added `route53_zone` module to dev environment
- Added `external_dns` module to dev environment
- Added `domain_name` variable to dev environment

---

## [2025-12-08] - AWS Load Balancer Controller & OIDC Provider

### Added
- **AWS Load Balancer Controller Module** (`terraform/modules/aws-load-balancer-controller/`)
  - IRSA (IAM Roles for Service Accounts) setup for secure AWS API access
  - IAM policy from official AWS source for ALB/NLB management
  - IAM role with OIDC trust policy for ServiceAccount authentication
  - Helm release for controller deployment in kube-system namespace
  - Configurable replicas (default: 2) for high availability
  - IP target type for direct pod traffic (VPC CNI optimized)

- **EKS OIDC Provider** (`terraform/modules/eks/`)
  - Added `aws_iam_openid_connect_provider` resource for IRSA support
  - Uses TLS certificate thumbprint from EKS cluster identity
  - New outputs: `oidc_provider_arn`, `oidc_provider`, `cluster_name`

- **VPC Cluster Tagging Fix**
  - Added `eks_cluster_name` variable to VPC module
  - Fixed subnet tags to use actual cluster name for ALB discovery
  - Changed empty string tags `""` to `null` for cleaner AWS tags

- **Helm Provider Configuration**
  - Added Helm provider to dev environment using EKS cluster auth
  - Uses `data.aws_eks_cluster_auth` for temporary token authentication
  - No kubeconfig file required (CI/CD friendly)

- **Test Manifests** (`test-manifest/`)
  - `deployment.yaml` - nginx test deployment
  - `service.yaml` - ClusterIP service
  - `ingress.yaml` - ALB Ingress with annotations

### Changed
- VPC module now requires `eks_cluster_name` input
- Dev environment uses locals for cluster name consistency
- Subnet tags now correctly reference the EKS cluster name

### Technical Implementation
```hcl
# IRSA Setup
resource "aws_iam_role" "alb_controller" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# Helm Release
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  # ...
}
```

### Benefits
- **Ingress Support**: Create ALBs from Kubernetes Ingress resources
- **Modern Architecture**: IRSA instead of node IAM roles
- **Secure**: Least privilege with specific ServiceAccount
- **Production Ready**: HA controller deployment with 2 replicas

---

## [2025-12-04] - Dynamic AZ Fetching & Validation

### Added
- **Dynamic AZ Fetching from AWS**
  - Uses `data.aws_availability_zones` to auto-fetch available AZs
  - Module now works in any region without hardcoded AZs
  - Falls back to data source when `var.availability_zones` is null

- **AZ Validation**
  - Validates user-provided AZs exist in the current region
  - Clear error message during `terraform plan` if invalid AZs passed
  - Uses `tobool()` trick for runtime validation with descriptive errors

- **New `az_count` Variable**
  - Controls how many AZs to use (default: 3)
  - Works with both user-provided and auto-fetched AZs
  - Uses `min()` to prevent exceeding available AZs

### Changed
- Renamed `total_number_of_az` to `az_count` (cleaner naming)
- `availability_zones` variable now defaults to `null` (triggers auto-fetch)
- Refactored locals for better readability:
  - `az_source`: Determines where AZs come from
  - `availability_zones`: Final list limited by `az_count`

### Technical Implementation
```hcl
# Validate AZs are available in region
invalid_azs = var.availability_zones != null ? [
  for az in var.availability_zones : az
  if !contains(data.aws_availability_zones.available.names, az)
] : []

# Hybrid AZ source (user-provided or AWS-fetched)
az_source = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available.names
availability_zones = slice(local.az_source, 0, min(var.az_count, length(local.az_source)))
```

### Benefits
- **Region-Agnostic**: Deploy to any region without code changes
- **Validation**: Catch invalid AZ errors at plan time, not apply time
- **Flexibility**: Override AZs when needed, auto-fetch when not
- **Cleaner Code**: Better variable names and separated logic

---

## [2025-12-01] - EKS Module & Access Management

### Added
- **EKS Module** (`terraform/modules/eks/`)
  - EKS Cluster with API authentication mode
  - Managed Node Groups with configurable scaling
  - Cluster IAM role with `AmazonEKSClusterPolicy`
  - Node group IAM role with worker policies
  - Full control plane logging (api, audit, authenticator, controllerManager, scheduler)
  - Public + private endpoint access

- **Access Entries for API Authentication**
  - `aws_eks_access_entry` resource for IAM principal mapping
  - `aws_eks_access_policy_association` for fine-grained permissions
  - Support for cluster-wide or namespace-scoped access
  - Available policies: ClusterAdmin, Admin, Edit, View

- **Configurable Node Groups**
  - `node_group_scaling_config`: desired, min, max sizes
  - `node_group_instance_types`: List of EC2 instance types
  - `node_group_capacity_type`: ON_DEMAND or SPOT support
  - `node_group_update_config`: Rolling update settings

- **EKS Module Documentation**
  - Comprehensive README with architecture diagram
  - Usage examples (basic, production, cost-optimized)
  - Input/output tables with all variables
  - Access management explanation
  - Cost estimation tables
  - Troubleshooting guide

- **Dev Environment EKS Integration**
  - `terraform.tfvars` for sensitive access entries (gitignored)
  - `terraform.tfvars.example` template for others
  - `variables.tf` with `eks_access_entries` variable

### Technical Implementation
- **API Authentication Mode** (modern approach, not ConfigMap)
- **Access Entry Pattern**:
  ```hcl
  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::ACCOUNT_ID:user/USERNAME"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }
  ```
- **Dynamic Access Entries**: Uses `for_each` over `var.access_entries` map
- **Implicit Dependencies**: Node group depends on IAM policy attachments

### Benefits
- **Modern Auth**: API mode for better AWS Console/CLI/Terraform management
- **Cost Flexibility**: SPOT instances for dev, ON_DEMAND for production
- **Security**: Sensitive credentials in gitignored tfvars
- **Observability**: All control plane logs enabled

---

## [2025-11-28] - Dynamic Subnet Generation & Module Documentation

### Added
- **Dynamic Subnet Generation**
  - Replaced hardcoded subnet list with `cidrsubnet()` function
  - Subnets now auto-calculated from `vpc_cidr_block` variable
  - Uses `ceil(log(n, 2))` to determine optimal subnet mask
  - Supports any VPC CIDR - subnets adjust automatically

- **Configurable Subnet Counts**
  - New `subnet_config` variable object:
    ```hcl
    subnet_config = {
      number_of_public_subnets  = 3
      number_of_private_subnets = 3
    }
    ```
  - Flexible public/private ratio (e.g., 4 public + 3 private)

- **NAT Gateway HA Toggle**
  - New `enable_ha_nat_gateways` boolean variable
  - `true`: NAT Gateway per AZ (~$96/month) - for production
  - `false`: Single NAT Gateway (~$32/month) - for dev/staging
  - Automatic routing adjustment based on mode

- **VPC Module README**
  - Comprehensive module documentation
  - Architecture diagram (ASCII art)
  - Usage examples (basic, custom, cost-optimized)
  - Input/output tables
  - Dynamic subnet calculation explanation
  - Cost estimation table

- **Locals Block for Computed Values**
  - `local.total_subnets`: Sum of public + private counts
  - `local.new_bits`: Auto-calculated subnet bits
  - `local.vpc_subnets`: Dynamically generated subnet list
  - `local.public_subnets`: Filtered public subnet map
  - `local.nat_gateway_subnets`: HA or single NAT based on toggle

### Changed
- Removed hardcoded `vpc_subnets` variable (now computed in locals)
- `availability_zones` moved to variable (was hardcoded)
- Renamed `external_traffic_cidr_block` to `internet_cidr_block`
- Updated dev environment to use custom CIDR (`192.168.0.0/16`)
- Dev now uses single NAT Gateway (`enable_ha_nat_gateways = false`)

### Technical Implementation
- **Dynamic CIDR Calculation**:
  ```hcl
  new_bits = ceil(log(local.total_subnets, 2))
  cidr_block = cidrsubnet(var.vpc_cidr_block, local.new_bits, idx)
  ```
- **AZ Distribution**: `var.availability_zones[idx % length(var.availability_zones)]`
- **Public/Private Split**: `idx < var.subnet_config.number_of_public_subnets`

### Benefits
- **Flexibility**: Change VPC CIDR without rewriting subnet configs
- **Cost Control**: Toggle HA NAT for different environments
- **Maintainability**: Single source of truth for subnet logic
- **Documentation**: Clear module README for team onboarding

---

## [2025-11-27] - NAT Gateway & Private Networking

### Added
- **NAT Gateway Infrastructure** (High Availability Setup)
  - 3 NAT Gateways (one per availability zone)
  - Each NAT Gateway deployed in corresponding public subnet
  - Elastic IPs allocated for each NAT Gateway
  - Tags include AZ identification for easy management

- **Private Route Tables**
  - Separate route table for each private subnet
  - Dynamic route configuration using advanced `for` loop with filtering
  - Routes private subnet traffic through NAT Gateway in same AZ
  - Ensures HA: Each AZ's private subnet uses its own AZ's NAT Gateway

- **Enhanced Tagging Strategy**
  - Introduced `resource_tag` variable for common tags across all resources
  - Uses `merge()` function to combine common tags with resource-specific tags
  - All resources now tagged with:
    - `ManagedBy = "Terraform"`
    - `Project = "production-eks-platform"`
    - `Environment` (dev/staging/prod)
    - Resource-specific `Name` tags

- **Kubernetes-Ready Subnet Tags**
  - Public subnets tagged with `kubernetes.io/role/elb = "1"` for ELB placement
  - Private subnets tagged with `kubernetes.io/role/internal-elb = "1"` for internal ELBs
  - All subnets tagged with `kubernetes.io/cluster/${var.environment}-eks-cluster = "shared"`

### Technical Implementation
- **NAT Gateway AZ Mapping**: Advanced for loop to match private subnets with NAT gateways by AZ
  ```hcl
  nat_gateway_id = [
    for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
    if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
  ][0]
  ```
- **Resource Naming Convention**: Improved with environment prefix and AZ suffix
- **Conditional Resource Creation**: Leveraged `for_each` with `if` filters for public/private resources

### Changed
- Renamed all resources from hyphenated names to snake_case (Terraform best practice)
  - `eks-vpc` → `eks_vpc`
  - `eks-gw` → `eks_gw`
  - `eks-subnets` → `eks_subnets`
- Subnet naming now includes type (public/private) and AZ for clarity
- Route table associations now properly separated for public vs private subnets

### Cost Considerations
- NAT Gateway costs: ~$32/month per NAT × 3 AZs = ~$96/month base cost
- Data transfer through NAT: $0.045/GB
- High availability setup chosen for production-grade architecture

### Architecture Benefits
- **Fault Tolerance**: Each AZ has independent NAT Gateway
- **No Single Point of Failure**: AZ failure doesn't affect other AZs' private subnet internet access
- **EKS Ready**: Subnet tagging enables automatic EKS integration
- **Clean Separation**: Public and private route tables completely isolated

---

## [2025-11-26] - VPC Module Foundation

### Added
- **VPC Module** (`terraform/modules/vpc/`)
  - Created reusable VPC module with parameterized configuration
  - VPC CIDR: `10.0.0.0/16` supporting ~65,000 IP addresses
  
- **Subnet Architecture**
  - 3 Public subnets across `us-west-2a`, `us-west-2b`, `us-west-2c`
    - `10.0.0.0/19` (us-west-2a)
    - `10.0.32.0/19` (us-west-2b)
    - `10.0.64.0/19` (us-west-2c)
  - 3 Private subnets across same AZs
    - `10.0.96.0/19` (us-west-2a)
    - `10.0.128.0/19` (us-west-2b)
    - `10.0.160.0/19` (us-west-2c)
  - Each subnet provides ~8,000 usable IPs (/19 CIDR)

- **Internet Gateway**
  - Created IGW for public internet access
  - Tagged as `eks-cluster-dev-gw`

- **Route Tables**
  - Public route table with `0.0.0.0/0` → Internet Gateway
  - Dynamic route table associations for public subnets only
  - Used conditional `for_each` to filter subnets based on `map_public_ip_on_launch`

- **Module Variables**
  - `vpc_cidr_block`: Configurable VPC CIDR
  - `vpc_subnets`: List of subnet objects with CIDR, AZ, and public IP settings
  - `environment`: Environment tag (dev/staging/prod)

- **Infrastructure as Code**
  - `.gitignore` for Terraform sensitive files
    - Excludes `.tfstate`, `.tfvars`, `.terraform/` directories
    - Protects AWS credentials and private keys
    - Excludes environment files and IDE configs

### Technical Decisions
- **Used `/19` subnet mask**: Provides 8,192 IPs per subnet (6 subnets from /16 VPC)
- **`for_each` with `tostring(idx)`**: Converted list indices to strings for Terraform compatibility
- **Conditional filtering**: Route tables only associate with public subnets using `if v.map_public_ip_on_launch`
- **Module-based architecture**: Enables reusability across dev/staging/prod environments

### DevOps Practices
- S3 remote state backend: `aws-eks-clusters-terraform-state`
- State file isolation per environment
- Modular design for maintainability

---