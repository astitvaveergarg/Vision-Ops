# Terraform - Azure AKS

> ⏳ **Status: IaC complete. Cluster not yet provisioned.**
> Active deployment is on GCP GKE. See `terraform/gcp/README.md`.

Terraform configuration for provisioning Azure Kubernetes Service (AKS) for VisionOps.

---

## Infrastructure Components

### VNet
- CIDR: `10.0.0.0/16`
- Dedicated subnet for AKS nodes
- Azure CNI (native VNet integration)
- Network Policy: Azure

### AKS Cluster
- Version: 1.28
- Private cluster (no public API endpoint)
- System-assigned managed identity
- Azure Key Vault Secrets Provider enabled

### Node Pools

**Dev:**
- `system`: 2-4× Standard_D4s_v3, auto-scale
- `general`: 1-3× Standard_D4s_v3, auto-scale
- `ml`: 1-3× Standard_F8s_v2 (CPU-optimised), auto-scale

**Prod:**
- `system`: 3-6× Standard_D8s_v3, 3 zones
- `general`: 2-10× Standard_D4s_v3, 3 zones
- `ml`: 2-15× Standard_F16s_v2, 3 zones

### CDN + WAF (Prod)
- Azure Front Door Premium → Internal LB
- Custom origin header validation
- WAF policy: rate limiting (100 req/min), OWASP rules

### Storage
- StorageClass: `managed` (Azure Disk, Standard HDD — dev)
- StorageClass: `managed-premium` (Azure Disk, Premium SSD — prod)

---

## Directory Structure

```
terraform/azure/
├── main.tf                 # Provider, storage backend, versions
├── variables.tf            # Input variables  
├── outputs.tf              # cluster_name, kubeconfig command, frontdoor_hostname
├── aks.tf                  # AKS cluster, node pools, VNet
├── frontdoor.tf            # Azure Front Door + WAF (prod only)
├── environments/
│   ├── dev.tfvars          # subscription_id ← must be updated before use
│   └── prod.tfvars
├── COMMANDS.md
└── README.md
```

---

## Prerequisites

```bash
# Azure CLI
az login
az account set --subscription <your-subscription-id>
az account show   # verify
```

> **Important**: Update `subscription_id` in `environments/dev.tfvars` and `prod.tfvars` before running.

---

## Deploy Dev Cluster

```bash
# 1. Create storage account for Terraform state
az login
az group create --name vision-terraform-state --location eastus
az storage account create \
  --name visionterraformstate \
  --resource-group vision-terraform-state \
  --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name visionterraformstate

# 2. Edit environments/dev.tfvars — set subscription_id

# 3. Deploy
cd terraform/azure
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
# ~10-15 minutes

# 4. Configure kubectl (private cluster — requires VPN or Azure Bastion)
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
```

> **Access**: AKS cluster has private API endpoint.
> See `PRIVATE_CLUSTER_GUIDE.md` for Azure VPN / Cloud Shell access options.

---

## Deploy VisionOps to AKS

```bash
# Install NGINX Ingress
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Create namespaces + secrets
kubectl apply -f k8s/secrets-dev.yaml

# Deploy
helmfile -e dev sync
kubectl get pods -A -w
```

---

## Cost Estimates

| Environment | Nodes | Estimated cost |
|-------------|-------|----------------|
| Dev | 2× Standard_D4s_v3 + 1× Standard_F8s_v2 | ~$250-350/month |
| Prod | HA multi-zone pool | ~$1,800-2,200/month |

> Destroy when not in use.

---

## Destroy

```bash
helmfile -e dev destroy
cd terraform/azure
terraform destroy -var-file=environments/dev.tfvars
```
