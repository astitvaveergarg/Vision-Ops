# Quick Reference - Terraform Commands

## Initial Setup (One-Time)

# 1. Create S3 backend
aws s3 mb s3://vision-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket vision-terraform-state --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name vision-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1

# 2. Initialize Terraform
cd terraform
terraform init
terraform validate

## Development Environment

# Plan
terraform plan -var-file=environments/dev.tfvars

# Apply
terraform apply -var-file=environments/dev.tfvars

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name vision-dev

# Destroy
terraform destroy -var-file=environments/dev.tfvars

## Production Environment

# Plan
terraform plan -var-file=environments/prod.tfvars

# Apply
terraform apply -var-file=environments/prod.tfvars

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name vision-prod

# Destroy
terraform destroy -var-file=environments/prod.tfvars

## Post-Deployment Setup

# Install ALB Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=vision-dev --set serviceAccount.create=true --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw alb_controller_role_arn)

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Deploy VisionOps
cd ..
helmfile -e dev apply

## Useful Commands

# Show outputs
terraform output

# Show specific output
terraform output cluster_name
terraform output cluster_endpoint

# Format code
terraform fmt -recursive

# View state
terraform show

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0

# Refresh state
terraform refresh -var-file=environments/dev.tfvars

# Taint resource (force recreate)
terraform taint module.eks.aws_eks_cluster.this[0]

# Check cluster access
kubectl get nodes
kubectl cluster-info
kubectl get pods -A
