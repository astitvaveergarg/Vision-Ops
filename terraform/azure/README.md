# VisionOps - Terraform Azure AKS Infrastructure

Terraform configuration for provisioning Azure Kubernetes Service (AKS) cluster for VisionOps ML platform.

## 📁 Structure

```
terraform-aks/
├── main.tf                     # Provider configuration
├── variables.tf                # Variable definitions
├── outputs.tf                  # Output values
├── aks.tf                      # AKS cluster & node pools
├── environments/
│   ├── dev.tfvars             # Dev environment config
│   └── prod.tfvars            # Prod environment config
├── COMMANDS.md                 # Quick reference
└── README.md
```

## 🚀 Prerequisites

1. **Azure CLI** - Configured with appropriate credentials
2. **Terraform** - Version >= 1.5.0
3. **kubectl** - To interact with cluster
4. **helm** - To deploy applications

### Install Tools

```bash
# Azure CLI
# Windows: Download from https://aka.ms/installazurecliwindows
# macOS: brew install azure-cli
# Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login
az login
az account set --subscription <subscription-id>

# Terraform
brew install terraform  # macOS
# or download from https://terraform.io

# kubectl
brew install kubectl

# helm
brew install helm

# helmfile
brew install helmfile
```

## 🏗️ Infrastructure Components

### Resource Group
- Dedicated resource group for all AKS resources
- Additional node resource group created automatically

### Virtual Network
- **CIDR**: 10.0.0.0/16 (dev), 10.1.0.0/16 (prod)
- **Subnet**: Dedicated subnet for AKS nodes
- **CNI**: Azure CNI for native VNet integration
- **Network Policy**: Azure Network Policy

### AKS Cluster
- **Version**: 1.28
- **Identity**: System-assigned managed identity
- **Auto-upgrade**: Patch (dev), Stable (prod)
- **Azure AD**: Optional RBAC integration
- **Key Vault Secrets Provider**: Enabled

### Node Pools

**Development:**
- `system`: 2-4 nodes, Standard_D4s_v3, auto-scaling
- `general`: 1-3 nodes, Standard_D4s_v3, auto-scaling
- `ml`: 1-3 nodes, Standard_F8s_v2 (CPU-optimized), auto-scaling

**Production:**
- `system`: 3-6 nodes, Standard_D8s_v3, auto-scaling, 3 zones
- `general`: 2-5 nodes, Standard_D8s_v3, auto-scaling, 3 zones
- `ml`: 2-10 nodes, Standard_F16s_v2 (dedicated for inference), 3 zones, tainted
- `monitoring`: 2-3 nodes, Standard_D4s_v3, auto-scaling, 2 zones

### Storage
- **StorageClass**: managed-premium (default)
- **CSI Driver**: Azure Disk CSI driver
- **Type**: Premium_LRS

### Monitoring
- **Log Analytics**: Integrated for container insights
- **Retention**: 30 days (dev), 90 days (prod)
- **Azure Monitor**: Container insights enabled

## 📋 Setup Instructions

### 1. Configure Subscription

Edit `environments/dev.tfvars` and `environments/prod.tfvars`:

```hcl
subscription_id = "YOUR-SUBSCRIPTION-ID"
```

Get your subscription ID:
```bash
az account list --output table
az account show --query id -o tsv
```

### 2. Create Storage Backend

```bash
# Create resource group
az group create --name vision-terraform-state --location eastus

# Create storage account
az storage account create \
  --name visionterraformstate \
  --resource-group vision-terraform-state \
  --location eastus \
  --sku Standard_LRS

# Create container
az storage container create \
  --name tfstate \
  --account-name visionterraformstate
```

### 3. Initialize Terraform

```bash
cd terraform-aks

# Initialize
terraform init

# Validate configuration
terraform validate
```

### 4. Review Plan

```bash
# Development
terraform plan -var-file=environments/dev.tfvars

# Production
terraform plan -var-file=environments/prod.tfvars
```

### 5. Apply Infrastructure

```bash
# Development (estimated cost: ~$400/month)
terraform apply -var-file=environments/dev.tfvars

# Production (estimated cost: ~$1,500/month)
terraform apply -var-file=environments/prod.tfvars
```

**⏱️ Provisioning Time**: ~10-15 minutes

### 6. Configure kubectl

```bash
# Get configuration command from output
terraform output configure_kubectl

# Run the command
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks

# Verify access
kubectl get nodes
kubectl get namespaces
```

## 🔧 Post-Deployment Setup

### 1. Install NGINX Ingress Controller

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Get external IP
kubectl get svc -n ingress-nginx
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
kind: ClusterIssuer
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
          class: nginx
EOF
```

### 3. Configure Azure Key Vault (Optional)

```bash
# Enable Key Vault integration
kubectl apply -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: $(terraform output -raw kubelet_identity)
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-tenant-id>"
EOF
```

### 4. Deploy VisionOps Application

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
| AKS Control Plane | - | 1 | $0 (Free tier) |
| System Nodes | Standard_D4s_v3 | 2-4 | $210 |
| General Nodes | Standard_D4s_v3 | 1-3 | $105 |
| ML Nodes | Standard_F8s_v2 | 1-3 | $130 |
| Managed Disks | Premium SSD | 400 GB | $60 |
| Bandwidth | - | ~100 GB | $9 |
| Log Analytics | - | 5 GB/day | $15 |
| **Total** | | | **~$529/month** |

### Production Environment
| Resource | Type | Quantity | Monthly Cost |
|----------|------|----------|--------------|
| AKS Control Plane | Uptime SLA | 1 | $73 |
| System Nodes | Standard_D8s_v3 | 3-6 | $630 |
| General Nodes | Standard_D8s_v3 | 2-5 | $420 |
| ML Nodes | Standard_F16s_v2 | 2-10 | $650 |
| Monitoring Nodes | Standard_D4s_v3 | 2-3 | $210 |
| Managed Disks | Premium SSD | 1 TB | $150 |
| Bandwidth | - | ~500 GB | $45 |
| Log Analytics | - | 30 GB/day | $90 |
| **Total** | | | **~$2,268/month** |

> **Note**: Costs are estimates and may vary based on actual usage, region, and Azure pricing changes.

## 🔐 Security Best Practices

### 1. Enable Azure AD Integration

Edit `environments/prod.tfvars`:
```hcl
enable_azure_ad = true
azure_ad_admin_group_ids = [
  "your-admin-group-object-id"
]
```

### 2. Configure Network Security Groups

```bash
# NSGs are managed automatically by AKS
# View node NSG
az network nsg list --resource-group $(terraform output -raw node_resource_group)
```

### 3. Enable Azure Policy

```bash
# Already enabled for prod in terraform
# View policies
az policy assignment list --resource-group vision-prod-rg
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

### Update Node Pool Size

```bash
# Via Terraform
vim environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars

# Via Azure CLI (immediate)
az aks nodepool scale \
  --resource-group vision-dev-rg \
  --cluster-name vision-dev-aks \
  --name ml \
  --node-count 5
```

### Upgrade Kubernetes Version

```bash
# Check available versions
az aks get-upgrades --resource-group vision-dev-rg --name vision-dev-aks

# Update kubernetes_version in tfvars
kubernetes_version = "1.29"

# Apply upgrade
terraform apply -var-file=environments/dev.tfvars
```

## 🗑️ Cleanup

### Destroy Infrastructure

```bash
# Delete VisionOps application first
helmfile -e dev destroy

# Wait for LoadBalancers to be deleted
kubectl get svc -A | grep LoadBalancer

# Destroy AKS cluster
terraform destroy -var-file=environments/dev.tfvars
```

**⏱️ Destruction Time**: ~10 minutes

## 📈 Monitoring

### Azure Monitor
```bash
# View container insights
az aks show --resource-group vision-dev-rg --name vision-dev-aks --query "addonProfiles.omsagent"

# Open in portal
az aks browse --resource-group vision-dev-rg --name vision-dev-aks
```

### Node Metrics
```bash
# Install metrics-server (usually pre-installed)
kubectl top nodes
kubectl top pods -A
```

### View Logs
```bash
# Node logs via Azure Monitor
az monitor log-analytics query \
  --workspace $(terraform output -raw log_analytics_workspace_id) \
  --analytics-query "ContainerLog | where TimeGenerated > ago(1h) | limit 100"
```

## 🔍 Troubleshooting

### Nodes Not Ready
```bash
# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# Check AKS health
az aks show --resource-group vision-dev-rg --name vision-dev-aks --query "powerState"

# View node pool status
az aks nodepool list --resource-group vision-dev-rg --cluster-name vision-dev-aks -o table
```

### kubectl Connection Issues
```bash
# Reconfigure kubectl
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks --overwrite-existing

# Test connection
kubectl cluster-info

# Check RBAC permissions
kubectl auth can-i get pods --all-namespaces
```

### Storage Issues
```bash
# Check StorageClass
kubectl get storageclass

# Check CSI driver
kubectl get pods -n kube-system | grep csi

# Check PVCs
kubectl get pvc -A
```

## 📚 Additional Resources

- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CNI Networking](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure Monitor for Containers](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)

---

**Last Updated**: February 13, 2026  
**Terraform Version**: >= 1.5.0  
**AKS Version**: 1.28
