# infraopsfleet — opsfleettech EKS + Karpenter Infrastructure

Production-grade Terraform infrastructure for deploying an Amazon EKS cluster with Karpenter autoscaling, supporting both AMD64 and ARM64 (Graviton) worker nodes.

## 🏗️ Architecture Overview

This infrastructure provides:

- **Dedicated VPC** with 3 private subnets across multiple AZs
- **Amazon EKS cluster** (configurable; examples use v1.34)
- **Karpenter** (installed via Helm — chart version pinned in `karpenter.tf`, e.g. 0.16.3)
- **Dual-architecture support** - AMD64 and ARM64 (Graviton) nodes
- **Cost optimization** through Spot instances and Graviton processors
- **Security best practices** with IAM roles and Pod Identity
- **Two-stage deployment** for reliable infrastructure setup

## 📋 Prerequisites

Ensure you have the following tools installed and configured (versions in repository assumed):

- **AWS CLI** (v2.0+) - [Installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (≥ 1.5) - [Installation guide](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- **kubectl** (matching your EKS Kubernetes version) - [Installation guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (v3.0+) - [Installation guide](https://helm.sh/docs/intro/install/)

### AWS Authentication

Configure your AWS credentials using one of these methods:

```bash
# Option 1: AWS CLI configuration
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="eu-west-1"

# Option 3: IAM roles (recommended for production)
# Use AWS IAM roles with appropriate permissions
```

### Required AWS Permissions

Your AWS credentials need the following permissions (examples — grant least privilege where possible):
- EKS cluster management (create/update/delete clusters and add-ons)
- VPC, subnet, route table, Internet/NAT Gateway management
- IAM role, instance profile and policy management (for nodes, Karpenter IRSA)
- EC2 instance and launch template management (instances, instance profiles, security groups)
- AutoScaling / Spot Fleet permissions (if using Spot)
- SQS / EventBridge only if your workloads use them (Karpenter IAM policies in this repo request SQS in some setups)

If you require additional permissions for other AWS services used by workloads (EBS, S3, RDS, etc.), add those as needed.

## 🚀 Quick Start

## Environments

This repo includes a `Makefile` to simplify common workflows. See the `Makefile` targets for exact commands; examples below assume the repo root.

Development (example flow)

```bash
# 1. Clone and enter the repository
git clone <repo-url>
cd infraopsfleet

# 2. Initialize & deploy infrastructure (Stage A: VPC, EKS, IAM, node groups)
# Initialize and validate
make init-validate
# (optional) view plan
make plan-dev         # full plan for dev (no -target)
make plan-staging     # plan for staging
# deploy
make deploy-dev

# 3. Configure kubectl access
aws eks --region eu-west-1 update-kubeconfig --name $(terraform output -raw cluster_name)

# 4. Install Karpenter (Stage B) and apply provisioners
make karpenter-dev
# Provisioners: apply rendered YAMLs from karpenter-provisioners/
kubectl apply -f karpenter-provisioners/

# 5. Verify
kubectl get nodes -o wide
kubectl -n karpenter get pods
```

Notes:
- The `Makefile` exposes environment-specific targets (e.g., `deploy-dev`, `karpenter-dev`). Use `make help` to list available targets.
- Provisioners/Catalog: this repository stores rendered provisioner YAML in `karpenter-provisioners/` — apply that directory after Karpenter is installed. Alternatively run the separate `provisioners/` Terraform working dir if you use Terraform-managed manifests (deprecated in this branch).

## 📁 Repository Structure

Current top-level tree (important files and folders):

```
. 
├── env/                       # per-environment Terraform (dev, prod)
├── karpenter-provisioners/    # rendered provisioner YAMLs (apply with kubectl)
├── karpenter/                 # Karpenter helpers, nodeclasses/nodepools
├── modules/                   # Terraform modules (vpc, eks, iam, karpenter, ...)
├── tests/                     # small test workloads (test-amd64, test-arm64)
├── Makefile                   # deployment automation targets
├── providers.tf               # providers
├── variables.tf               # global variables
├── locals.tf                  # computed locals (cluster_name)
├── eks.tf                     # EKS and nodegroups
├── karpenter.tf               # Karpenter IAM + Helm release
├── vpc.tf                     # VPC and subnets
└── README.md
```

## 🎯 Two-Stage Deployment Process

We intentionally separate the run into two stages to avoid Kubernetes provider/CRD timing problems.

### Stage A — Infrastructure (required first)
- Create VPC, private/public subnets, and networking
- Deploy EKS cluster and node groups (this bootstraps nodes for scheduling)
- Create IAM roles, OIDC provider and instance profile(s)

Notes: node groups / nodes are created during Stage A in this repo's flow (so nodes may already exist before Karpenter runs).

### Stage B — Karpenter + Provisioners (run after Stage A completes)
- Install Karpenter via Helm (the Helm release in `karpenter.tf` installs CRDs and the controller)
- Apply Karpenter Provisioner CRs (either via `karpenter-provisioners/` rendered YAMLs or via a separate Terraform working dir when used)

This ordering prevents attempting to create CRs before the Karpenter CRDs/controllers are present.

## 🛠️ Available Commands

### Environment Management

```bash
# Development
make init-validate       # Initialize and validate Terraform
make plan-dev            # Show full plan for dev (no -target)
make plan-staging        # Show plan for staging
make deploy-dev          # Deploy dev infrastructure (Stage A)
make karpenter-dev       # Deploy Karpenter for dev (Stage B)
make destroy-dev         # Destroy dev infrastructure

# Targeted destroys (examples)
make destroy-karpenter-dev  # Destroy only karpenter in dev
make destroy-eks-dev        # Destroy only EKS module in dev

# Production
make deploy-prod         # Deploy prod infrastructure (Stage A)
make karpenter-prod      # Deploy Karpenter for prod (Stage B)
make destroy-prod        # Destroy prod infrastructure
make plan-prod           # Show full plan for prod (no -target)

# Targeted destroys for prod
make destroy-karpenter-prod
make destroy-eks-prod
```

## 📊 Testing Node Scheduling

A small smoke-test is included in `tests/`. Use these manifests to validate scheduling across architectures.

```bash
# Deploy the two test deployments (amd64 + arm64)
kubectl apply -f tests/

# Wait for rollouts
kubectl rollout status deployment/test-amd64 --timeout=120s
kubectl rollout status deployment/test-arm64 --timeout=120s

# Inspect pods and node architectures
kubectl get pods -o wide -A
kubectl get nodes -o wide -L kubernetes.io/arch
```

## 🏛️ Architecture Details

### Networking
- **VPC CIDRs**: configured per-environment (see `env/dev/variables.tf` and `env/prod/variables.tf`)
- **Subnets**: 3 private subnets across multiple AZs (configurable in `env/*`)
- **NAT Gateway**: single NAT in dev, per-AZ in prod (see environment configs)
- **Security Groups**: optimized for EKS and Karpenter

### EKS Configuration
- **Version**: 1.34 (dev), 1.33 (prod) - configurable
- **Endpoint**: Public + Private access enabled
- **Add-ons**: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver
- **Encryption**: KMS encryption for etcd secrets

### Karpenter NodePools
- **Instance types**: example instance types are declared under `karpenter/nodepools/` and in the `modules/eks` nodegroup definitions. In this branch the dev `aws_eks_node_group` examples use `t3.small` (amd64) and `m6g.medium` (arm64); adjust per-environment as needed.
- **Capacity Types**: Spot + On‑Demand instances (configurable)
- **AMI Family**: Bottlerocket is used by default in this repo for both architectures

### Cost Optimization
- Single NAT Gateway in development
- Spot instances enabled by default
- Graviton (ARM64) instances for better price/performance
- Karpenter's intelligent provisioning and de-provisioning

## 🔒 Security Features

- **IAM Roles**: Separate roles for cluster, nodes, and Karpenter
- **Pod Identity**: Secure service account authentication
- **Security Groups**: Minimal required access
- **Network Isolation**: Private subnets for worker nodes
- **Encryption**: KMS encryption for EKS secrets
- **Instance Profiles**: Properly scoped EC2 permissions

## 🌍 Multi-Environment Support

### Development Environment
- Cost-optimized configuration
- Single NAT Gateway
- Latest Kubernetes version (1.34)
- Relaxed resource limits

### Production Environment
- High-availability setup
- NAT Gateway per AZ
- Stable Kubernetes version (1.33)
- Production-grade resource limits
- Additional monitoring and logging

## 📚 Configuration

### Environment Variables
```bash
export AWS_REGION=eu-west-1              # AWS region
export KUBE_CONFIG_PATH=~/.kube/config   # kubectl config
```

### Customization

Key configuration files:
- `env/dev/variables.tf` - Development settings
- `env/prod/variables.tf` - Production settings
- `karpenter/nodepools/` - NodePool instance types and limits
- `karpenter/nodeclasses/` - EC2 configuration and AMI settings

## 🩺 Health Checks and Validation

### After Stage A (Infrastructure):
```bash
# Check EKS cluster status (uses the configured cluster name output)
aws eks describe-cluster --name $(terraform output -raw cluster_name) --region eu-west-1 --query "cluster.status"

# Verify add-on versions
aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name coredns
```

### After Stage B (Karpenter):
```bash
# Check Karpenter installation
kubectl get crd | grep karpenter
kubectl -n karpenter get pods

# Verify NodePools and EC2NodeClasses (if using the nodeclasses/nodepools helpers)
kubectl get nodepool,ec2nodeclass || true

```

## 🐛 Troubleshooting

### Common Issues

**1. Terraform provider authentication errors:**
```bash
# Ensure AWS CLI is configured
aws sts get-caller-identity

# Check environment variables
env | grep AWS
```

**2. kubectl cannot connect to cluster:**
```bash
# Update kubeconfig
aws eks --region eu-west-1 update-kubeconfig --name <cluster_name>

# Verify connection
kubectl cluster-info
```

**3. Karpenter not provisioning nodes:**
```bash
# Check Karpenter controller logs
kubectl -n karpenter logs deployment/<deployment_name>

# Verify NodePool and EC2NodeClass
kubectl describe nodepool <cluster_name>
kubectl describe <nodenames>
```

**4. Pods stuck in Pending state:**
```bash
# Check pod events
kubectl describe pod <pod-name>

# Check NodePool limits
kubectl get nodepool -o yaml
```

## 🗑️ Cleanup

To destroy all resources:

```bash
# Development
make destroy-dev

# Production
make destroy-prod

# Clean local Terraform files
make clean
```

## 📝 Important Notes

- **Local State**: This setup uses local state files for the assessment. In production, consider using [S3 backend with state locking](https://learn.hashicorp.com/tutorials/terraform/aws-remote).
- **Costs**: Monitor your AWS costs, especially with Karpenter autoscaling enabled.
- **Updates**: Regularly update Terraform modules and Karpenter versions.
- **Backup**: Consider implementing backup strategies for critical workloads.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

**opsfleettech** - Building scalable, cost-effective Kubernetes infrastructure on AWS
