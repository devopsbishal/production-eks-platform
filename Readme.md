# 🚀 Production-Ready EKS Platform

> A comprehensive, production-grade Kubernetes platform built on AWS EKS, demonstrating enterprise DevOps practices, Infrastructure as Code, GitOps workflows, and complete observability.

## 📋 Table of Contents
- [Overview](#-overview)
- [Architecture](#️-architecture)
- [Tech Stack](#️-tech-stack)
- [Current Progress](#-current-progress)
- [Roadmap](#️-roadmap)
- [Getting Started](#-getting-started)
- [Notes](#-notes)
- [Contact](#-contact)

## 🎯 Overview

This project showcases the implementation of a production-grade Kubernetes platform on AWS EKS, following industry best practices for:
- Multi-environment infrastructure management
- High availability and fault tolerance
- GitOps-based application deployment
- Comprehensive observability and monitoring
- Cost optimization and autoscaling
- Security and compliance

**Target Use Cases:**
- Self-service developer platforms
- Microservices architectures
- CI/CD pipelines
- MLOps workloads

## 🏗️ Architecture
> 📖 Detailed architecture decisions documented in [Architecture Decision Records](https://github.com/devopsbishal/production-eks-platform/blob/main/docs/DECISIONS.md)

### Infrastructure Layout
```
┌─────────────────────────────────────────────────────────────────┐
│                    VPC: 10.0.0.0/16 (65,536 IPs)                │
│                         Region: us-west-2                        │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
│   Availability Zone  │ │   Availability Zone  │ │   Availability Zone  │
│      us-west-2a      │ │      us-west-2b      │ │      us-west-2c      │
├──────────────────────┤ ├──────────────────────┤ ├──────────────────────┤
│ 🌐 Public Subnet     │ │ 🌐 Public Subnet     │ │ 🌐 Public Subnet     │
│  10.0.0.0/19         │ │  10.0.32.0/19        │ │  10.0.64.0/19        │
│  (8,192 IPs)         │ │  (8,192 IPs)         │ │  (8,192 IPs)         │
│  • Internet Gateway  │ │  • Load Balancers    │ │  • NAT Gateways      │
│  • Bastion Hosts     │ │  • ALB/NLB           │ │                      │
├──────────────────────┤ ├──────────────────────┤ ├──────────────────────┤
│ 🔒 Private Subnet    │ │ 🔒 Private Subnet    │ │ 🔒 Private Subnet    │
│  10.0.96.0/19        │ │  10.0.128.0/19       │ │  10.0.160.0/19       │
│  (8,192 IPs)         │ │  (8,192 IPs)         │ │  (8,192 IPs)         │
│  • EKS Worker Nodes  │ │  • EKS Worker Nodes  │ │  • EKS Worker Nodes  │
│  • Application Pods  │ │  • Application Pods  │ │  • Application Pods  │
└──────────────────────┘ └──────────────────────┘ └──────────────────────┘

📊 Remaining IPs: 10.0.192.0/18 (16,384 IPs reserved for future use)
```

**Design Decisions:**
- **3 Availability Zones**: High availability and fault tolerance across physical locations
- **Public Subnets** (10.0.0.0/19, /19, /19): Internet-facing resources
  - Direct internet access via Internet Gateway
  - Host load balancers (ALB/NLB) and bastion hosts
  - Auto-assign public IPs enabled
- **Private Subnets** (10.0.96.0/19, /19, /19): Secure application tier
  - EKS worker nodes and pods (no direct internet access)
  - Internet access via NAT Gateway (outbound only)
  - Enhanced security posture
- **/19 CIDR blocks**: ~8,000 usable IPs per subnet (supports hundreds of pods per AZ)
- **Reserved space**: 25% of VPC CIDR available for future expansion (DB tier, cache layer, etc.)

## 🛠️ Tech Stack

**Infrastructure:**
- Terraform 1.x for Infrastructure as Code
- AWS VPC, EKS, S3 (remote state)
- Multi-AZ architecture with dynamic subnet generation

**Kubernetes Platform:**
- EKS 1.34 with API authentication mode
- Managed Node Groups (SPOT/ON_DEMAND)
- Access Entries for IAM-based cluster access
- Full control plane logging
- AWS Load Balancer Controller (IRSA-based)
- OIDC Provider for pod IAM roles

**Planned:**
- ArgoCD for GitOps
- Prometheus + Grafana for monitoring
- Karpenter for autoscaling
- External Secrets Operator
- cert-manager
- EBS CSI Driver

## 📊 Current Progress

### Week 1 - Infrastructure Foundation
- [x] Repository structure setup
- [x] Terraform VPC module with 3 public + 3 private subnets
- [x] Internet Gateway configuration
- [x] Route tables and associations for public subnets
- [x] S3 backend for Terraform state
- [x] Comprehensive .gitignore for Terraform security
- [x] NAT Gateways for private subnets (HA toggle - single or multi-AZ)
- [x] Private route tables with NAT Gateway routing
- [x] EKS-ready subnet tagging
- [x] Dynamic subnet generation with `cidrsubnet()`
- [x] VPC module documentation (README)

### Week 2 - EKS Cluster
- [x] EKS cluster module with API authentication mode
- [x] Managed node groups with SPOT/ON_DEMAND support
- [x] IAM roles for cluster and node groups
- [x] Access entries for fine-grained cluster access
- [x] Control plane logging (api, audit, authenticator, controllerManager, scheduler)
- [x] EKS module documentation (README)
- [x] Gitignored tfvars for sensitive credentials
- [ ] Security groups and NACL refinement
- [ ] RBAC setup for team access

### Week 3 - Kubernetes Add-ons
- [x] AWS Load Balancer Controller module with IRSA
- [x] OIDC Provider for IAM Roles for Service Accounts
- [x] Helm provider configuration (no kubeconfig needed)
- [x] VPC subnet tagging fix for ALB discovery
- [x] Test manifests (Deployment, Service, Ingress)
- [x] ALB Controller module documentation (README)
- [ ] External DNS for Route53 integration
- [ ] EBS CSI Driver for persistent volumes

**Last Updated:** December 8, 2025

📝 See [detailed changelog](https://github.com/devopsbishal/production-eks-platform/blob/main/docs/CHANGELOG.md) for daily updates

## 🗓️ Roadmap

### Phase 1: Foundation (Weeks 1-3) ✅
- [x] VPC networking with dynamic subnets
- [x] NAT Gateways (HA toggle for cost optimization)
- [x] EKS cluster deployment with API auth mode
- [x] Managed node groups (SPOT/ON_DEMAND)
- [x] Access entries for IAM-based cluster access
- [x] AWS Load Balancer Controller (IRSA)
- [x] OIDC Provider for pod IAM roles
- [ ] External DNS
- [ ] EBS CSI Driver
- [ ] Security groups refinement

### Phase 2: GitOps & Automation (Weeks 4-5)
- [ ] ArgoCD installation
- [ ] GitOps repository structure
- [ ] Sample application deployment
- [ ] CI/CD integration

### Phase 3: Observability (Week 5)
- [ ] Prometheus & Grafana stack
- [ ] Loki for log aggregation
- [ ] Custom dashboards
- [ ] Alerting rules

### Phase 4: Advanced Features (Week 6)
- [ ] Karpenter autoscaling
- [ ] External Secrets integration
- [ ] Cost optimization analysis
- [ ] Documentation & polish

## 🚀 Getting Started

### Prerequisites
- AWS Account with appropriate permissions
- AWS CLI configured
- Terraform >= 1.5
- kubectl
- S3 bucket for Terraform state: `aws-eks-clusters-terraform-state`

### Deployment
```bash
# Clone the repository
git clone https://github.com/devopsbishal/production-eks-platform.git
cd production-eks-platform

# Navigate to dev environment
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply infrastructure (currently VPC only)
terraform apply
```

## 📝 Notes

This is an active learning project built to demonstrate:
1. Production-grade infrastructure design
2. Terraform best practices (modules, remote state, workspaces)
3. AWS EKS architecture patterns
4. DevOps/SRE principles

**Status:** 🚧 Work in Progress - Week 2 of 6 (EKS Complete!)

## 📫 Contact

Created by **Bishal** - Aspiring Kubestronaut → Cloud/DevOps Engineer

[GitHub](https://github.com/devopsbishal) • [LinkedIn](https://www.linkedin.com/in/bishal-rayamajhi-02523a243)

---

⭐ Star this repo if you find it helpful!