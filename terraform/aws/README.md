# VisionOps - Terraform AWS EKS Infrastructure

Terraform configuration for provisioning AWS EKS cluster for VisionOps ML platform.

## 📁 Structure

```
terraform/
├── main.tf                     # Provider configuration
├── variables.tf                # Variable definitions
├── outputs.tf                  # Output values
├── eks.tf                      # EKS cluster & node groups
├── environments/
│   ├── dev.tfvars             # Dev environment config
│   └── prod.tfvars            # Prod environment config
└── README.md
```

## 🚀 Prerequisites

1. **AWS CLI** - Configured with appropriate credentials
2. **Terraform** - Version >= 1.5.0
3. **kubectl** - To interact with cluster
4. **helm** - To deploy applications

### Install Tools

```bash
# Terraform
brew install terraform  # macOS
# or download from https://terraform.io

# AWS CLI
brew install awscli
aws configure

# kubectl
brew install kubectl

# helm
brew install helm

# helmfile
brew install helmfile
```

## 🏗️ Infrastructure Components

### VPC
- **CIDR**: 10.0.0.0/16 (dev), 10.1.0.0/16 (prod)
- **Subnets**: Private and public across 2-3 AZs
- **NAT Gateway**: Single (dev), Multi-AZ (prod)
- **Tags**: Kubernetes ELB discovery tags

### EKS Cluster
- **Version**: 1.28
- **Endpoint**: Public access enabled
- **IRSA**: Enabled for pod IAM roles
- **Addons**: CoreDNS, kube-proxy, VPC-CNI, EBS CSI

### Node Groups

**Development:**
- `general`: 2-5 nodes, t3.large, ON_DEMAND
- `ml`: 1-3 nodes, c5.2xlarge, SPOT

**Production:**
- `general`: 3-6 nodes, t3.xlarge, ON_DEMAND
- `ml`: 2-10 nodes, c5.4xlarge, ON_DEMAND (dedicated for inference)
- `monitoring`: 2-3 nodes, t3.large, ON_DEMAND

### Storage
- **StorageClass**: GP3 (default)
- **EBS CSI Driver**: Enabled
- **Encryption**: Enabled by default

### IAM Roles
- EKS cluster role
- Node group roles
- EBS CSI driver IRSA role
- ALB controller IRSA role

## 📋 Setup Instructions

### 1. Create S3 Backend

First-time setup requires creating S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket
aws s3 mb s3://vision-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket vision-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name vision-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Initialize Terraform

```bash
cd terraform

# Initialize
terraform init

# Validate configuration
terraform validate
```

### 3. Review Plan

```bash
# Development
terraform plan -var-file=environments/dev.tfvars

# Production
terraform plan -var-file=environments/prod.tfvars
```

### 4. Apply Infrastructure

```bash
# Development (estimated cost: ~$300/month)
terraform apply -var-file=environments/dev.tfvars

# Production (estimated cost: ~$800/month)
terraform apply -var-file=environments/prod.tfvars
```

**⏱️ Provisioning Time**: ~15-20 minutes

### 5. Configure kubectl

```bash
# Get configuration command from output
terraform output configure_kubectl

# Run the command
aws eks update-kubeconfig --region us-east-1 --name vision-dev

# Verify access
kubectl get nodes
kubectl get namespaces
```

## 🔧 Post-Deployment Setup

### 1. Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install ALB controller
kubectl create namespace kube-system || true

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw alb_controller_role_arn)
```

### 2. Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind:ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: alb
EOF
```

### 3. Deploy VisionOps Application

```bash
# Return to project root
cd ..

# Deploy via Helmfile
helmfile -e dev apply    # For dev
helmfile -e prod apply   # For prod

# Check deployments
kubectl get pods -A
```

## 📊 Estimated Costs

### Development Environment
| Resource | Type | Quantity | Monthly Cost |
|----------|------|----------|--------------|
| EKS Cluster | - | 1 | $73 |
| EC2 Instances | t3.large | 3 | $150 |
| EC2 Instances | c5.2xlarge (SPOT) | 1 | $50 |
| EBS Volumes | gp3 | 200 GB | $20 |
| NAT Gateway | - | 1 | $32 |
| Data Transfer | - | ~100 GB | $9 |
| **Total** | | | **~$334/month** |

### Production Environment
| Resource | Type | Quantity | Monthly Cost |
|----------|------|----------|--------------|
| EKS Cluster | - | 1 | $73 |
| EC2 Instances | t3.xlarge | 5 | $375 |
| EC2 Instances | c5.4xlarge | 4 | $550 |
| EBS Volumes | gp3 | 700 GB | $70 |
| NAT Gateway | - | 3 | $96 |
| Data Transfer | - | ~500 GB | $45 |
| **Total** | | | **~$1,209/month** |

> **Note**: Costs are estimates and may vary based on actual usage, region, and AWS pricing changes.

## 🔐 Security Best Practices

### 1. Enable Encryption
```bash
# Encrypt EBS volumes (already enabled in terraform)
# Verify
kubectl get storageclass gp3 -o yaml | grep encrypted
```

### 2. Configure Security Groups
```bash
# Security groups are managed by Terraform
# Verify cluster security group
terraform output cluster_security_group_id
```

### 3. Enable Audit Logging
```bash
# Enable control plane logging
aws eks update-cluster-config \
  --name $(terraform output -raw cluster_name) \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### 4. Setup Secrets Management

```bash
# Create secrets for VisionOps
kubectl create namespace vision-infra

kubectl create secret generic minio-credentials \
  --from-literal=access-key=YOUR_ACCESS_KEY \
  --from-literal=secret-key=YOUR_SECRET_KEY \
  -n vision-infra

kubectl create secret generic redis-credentials \
  --from-literal=password=YOUR_REDIS_PASSWORD \
  -n vision-infra
```

## 🔄 Updating Infrastructure

### Update Node Group Size

```bash
# Edit tfvars file
vim environments/dev.tfvars

# Apply changes
terraform apply -var-file=environments/dev.tfvars
```

### Upgrade Kubernetes Version

```bash
# Update cluster_version in tfvars
cluster_version = "1.29"

# Apply upgrade
terraform apply -var-file=environments/dev.tfvars

# Upgrade nodes (automatic with managed node groups)
```

## 🗑️ Cleanup

### Destroy Infrastructure

```bash
# Delete VisionOps application first
helmfile -e dev destroy

# Wait for LoadBalancers to be deleted
kubectl get svc -A | grep LoadBalancer

# Destroy EKS cluster
terraform destroy -var-file=environments/dev.tfvars
```

**⏱️ Destruction Time**: ~15 minutes

## 📈 Monitoring

### CloudWatch Logs
```bash
# View control plane logs
aws logs tail /aws/eks/$(terraform output -raw cluster_name)/cluster --follow
```

### Node Metrics
```bash
# Install metrics-server (if not already)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# View node metrics
kubectl top nodes

# View pod metrics
kubectl top pods -A
```

## 🔍 Troubleshooting

### Nodes Not Joining Cluster
```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name $(terraform output -raw cluster_name) \
  --nodegroup-name general

# Check worker node logs
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=$(terraform output -raw cluster_name)" \
  --query 'Reservations[].Instances[].InstanceId'
```

### kubectl Connection Issues
```bash
# Reconfigure kubectl
aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name)

# Test connection
kubectl cluster-info

# Check IAM permissions
aws sts get-caller-identity
```

### Storage Issues
```bash
# Check EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi

# Check StorageClass
kubectl get storageclass

# Check PVCs
kubectl get pvc -A
```

## 📚 Additional Resources

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

**Last Updated**: February 13, 2026  
**Terraform Version**: >= 1.5.0  
**EKS Version**: 1.28
