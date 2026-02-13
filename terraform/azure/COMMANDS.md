# Quick Reference - Terraform AKS Commands

## Initial Setup (One-Time)

# 1. Login to Azure
az login
az account set --subscription <subscription-id>

# 2. Create storage account for backend
az group create --name vision-terraform-state --location eastus
az storage account create --name visionterraformstate --resource-group vision-terraform-state --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name visionterraformstate

# 3. Initialize Terraform
cd terraform-aks
terraform init
terraform validate

## Development Environment

# Plan
terraform plan -var-file=environments/dev.tfvars

# Apply
terraform apply -var-file=environments/dev.tfvars

# Configure kubectl
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks

# Destroy
terraform destroy -var-file=environments/dev.tfvars

## Production Environment

# Plan
terraform plan -var-file=environments/prod.tfvars

# Apply
terraform apply -var-file=environments/prod.tfvars

# Configure kubectl
az aks get-credentials --resource-group vision-prod-rg --name vision-prod-aks

# Destroy
terraform destroy -var-file=environments/prod.tfvars

## Post-Deployment Setup

# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

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
terraform output cluster_fqdn

# Format code
terraform fmt -recursive

# View state
terraform show

# Refresh state
terraform refresh -var-file=environments/dev.tfvars

# Check cluster access
kubectl get nodes
kubectl cluster-info
kubectl get pods -A

# View AKS logs
az aks show --resource-group vision-dev-rg --name vision-dev-aks
az aks get-upgrades --resource-group vision-dev-rg --name vision-dev-aks

# Scale node pool
az aks nodepool scale --resource-group vision-dev-rg --cluster-name vision-dev-aks --name ml --node-count 3

# Upgrade cluster
az aks upgrade --resource-group vision-dev-rg --name vision-dev-aks --kubernetes-version 1.29
