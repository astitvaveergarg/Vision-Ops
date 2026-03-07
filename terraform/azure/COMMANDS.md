# Quick Reference - Azure AKS Commands

> ⏳ IaC complete. Cluster not yet provisioned. Active deployment is GCP GKE.

## Prerequisites

```bash
az login
az account set --subscription <subscription-id>
az account show   # verify

# Update environments/dev.tfvars with your subscription_id
```

## Create State Backend (One-Time)

```bash
az group create --name vision-terraform-state --location eastus
az storage account create \
  --name visionterraformstate \
  --resource-group vision-terraform-state \
  --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name visionterraformstate
```

## Dev Cluster

```bash
cd terraform/azure
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars   # ~10-15 min

# kubectl (private cluster — needs Azure Bastion or VPN)
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
kubectl get nodes
```

## Deploy VisionOps

```bash
kubectl apply -f k8s/secrets-dev.yaml
helmfile -e dev sync
kubectl get pods -A -w
```

## Destroy

```bash
helmfile -e dev destroy
cd terraform/azure
terraform destroy -var-file=environments/dev.tfvars
```

## Prod Cluster

```bash
terraform apply  -var-file=environments/prod.tfvars
az aks get-credentials --resource-group vision-prod-rg --name vision-prod-aks
helmfile -e prod apply
terraform destroy -var-file=environments/prod.tfvars
```

## Useful Azure Commands

```bash
# List AKS clusters
az aks list --output table

# Scale node pool
az aks scale --resource-group vision-dev-rg \
  --name vision-dev-aks --node-count 3 --nodepool-name general

# Get Front Door hostname
terraform output frontdoor_endpoint_hostname

# Check node pool status
kubectl get nodes -L beta.kubernetes.io/instance-type,topology.kubernetes.io/zone
```
