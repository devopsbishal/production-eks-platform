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
- Multi-AZ architecture

**Kubernetes Platform (Planned):**
- EKS 1.30+
- ArgoCD for GitOps
- Prometheus + Grafana for monitoring
- Karpenter for autoscaling
- AWS Load Balancer Controller
- External Secrets Operator
- cert-manager

## 📊 Current Progress

### Week 1 - Infrastructure Foundation
- [x] Repository structure setup
- [x] Terraform VPC module with 3 public + 3 private subnets
- [x] Internet Gateway configuration
- [x] Route tables and associations for public subnets
- [x] S3 backend for Terraform state
- [x] Comprehensive .gitignore for Terraform security
- [ ] NAT Gateways for private subnets
- [ ] EKS cluster module
- [ ] Security groups and NACL

**Last Updated:** November 26, 2025

📝 See [detailed changelog](https://github.com/devopsbishal/production-eks-platform/blob/main/docs/CHANGELOG.md) for daily updates

## 🗓️ Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [x] VPC networking
- [ ] NAT Gateways
- [ ] EKS cluster deployment
- [ ] Node groups configuration
- [ ] RBAC setup

### Phase 2: GitOps & Automation (Weeks 3-4)
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

**Status:** 🚧 Work in Progress - Week 1 of 6

## 📫 Contact

Created by **Bishal** - Aspiring Kubestronaut → Cloud/DevOps Engineer

[GitHub](https://github.com/devopsbishal) • [LinkedIn](https://www.linkedin.com/in/bishal-rayamajhi-02523a243)

---

⭐ Star this repo if you find it helpful!