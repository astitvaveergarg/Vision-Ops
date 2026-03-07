# VisionOps GKE Terraform

Provisions a **private GKE cluster** on Google Cloud for VisionOps ML inference.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           GCP Project                   │
                    │                                         │
                    │  ┌─────────────────────────────────┐   │
                    │  │         VPC Network              │   │
                    │  │                                 │   │
                    │  │  ┌──────────────────────────┐  │   │
                    │  │  │   GKE Private Cluster    │  │   │
                    │  │  │                          │  │   │
                    │  │  │  ┌──────────────────┐   │  │   │
                    │  │  │  │  General Pool    │   │  │   │
                    │  │  │  │  e2-standard-4   │   │  │   │
                    │  │  │  │  Redis | MinIO   │   │  │   │
                    │  │  │  │  Prometheus      │   │  │   │
                    │  │  │  └──────────────────┘   │  │   │
                    │  │  │                          │  │   │
                    │  │  │  ┌──────────────────┐   │  │   │
                    │  │  │  │    ML Pool       │   │  │   │
                    │  │  │  │  e2-standard-4   │   │  │   │
                    │  │  │  │  vision-api      │   │  │   │
                    │  │  │  │  (YOLO inference)│   │  │   │
                    │  │  │  └──────────────────┘   │  │   │
                    │  │  └──────────────────────────┘  │   │
                    │  │               │                 │   │
                    │  │          Cloud NAT              │   │
                    │  │    (outbound internet access)   │   │
                    │  └─────────────────────────────────┘   │
                    │                                         │
                    │  Cloud Armor WAF (prod only)            │
                    └─────────────────────────────────────────┘
```

## Cost Estimate

| Environment | Nodes | Cost/hr | Cost/day |
|-------------|-------|---------|---------|
| Dev (zonal) | 1× e2-standard-4 | **~$0.16** | ~$3.84 |
| Prod (regional) | 2× e2-standard-4 + 2× c2-standard-8 | **~$0.65** | ~$15.60 |

**GKE zonal control plane is FREE.** Destroy the cluster when not testing to avoid charges.

With Google Cloud $300 free credit:
- Dev testing (4 hrs/day) → credit lasts **~470 days**
- Prod testing (4 hrs/day) → credit lasts **~115 days**

## Prerequisites

1. **Google Cloud account** with billing enabled (use $300 free credit)
2. **gcloud CLI** installed: https://cloud.google.com/sdk/docs/install
3. **Terraform >= 1.5.0**
4. **Helm >= 3.0** + **Helmfile**

## One-Time Setup

### 1. Authenticate

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Create Terraform State Bucket

```bash
gcloud storage buckets create gs://vision-terraform-state-gcp \
  --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://vision-terraform-state-gcp --versioning
```

### 3. Configure Your Project ID

Edit `environments/dev.tfvars`:
```hcl
project_id = "your-actual-project-id"  # ← change this
```

## Deploy Dev Cluster

```bash
cd terraform/gcp
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
# ⏱️ ~10-12 minutes

# Configure kubectl
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a \
  --project YOUR_PROJECT_ID

# Verify
kubectl get nodes
```

## Deploy VisionOps to GKE

```bash
# Create namespaces + secrets
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring

kubectl create secret generic minio-credentials \
  --from-literal=access-key=minioadmin123 \
  --from-literal=secret-key=minioadmin123 \
  -n vision-infra

kubectl create secret generic redis-credentials \
  --from-literal=password=redis123 \
  -n vision-infra

# Deploy everything
cd ../..
helmfile -e dev sync

# Port-forward to access API
kubectl port-forward -n vision-app svc/vision-api 8000:8000
curl http://localhost:8000/health
```

## Destroy (Stop Costs)

```bash
# Destroy K8s workloads first
helmfile -e dev destroy

# Destroy infrastructure
cd terraform/gcp
terraform destroy -var-file=environments/dev.tfvars
```

## Key Differences from AWS/Azure

| Feature | AWS EKS | Azure AKS | GCP GKE |
|---------|---------|-----------|---------|
| Control plane cost | $0.10/hr always | Free | Free (zonal) / $0.10/hr (regional) |
| kubectl config | `aws eks update-kubeconfig` | `az aks get-credentials` | `gcloud container clusters get-credentials` |
| Ingress controller | AWS Load Balancer Controller | NGINX/Azure LB | GKE Ingress (GLB) / NGINX |
| WAF | CloudFront + WAF | Front Door + WAF | Cloud Armor |
| Storage class | `gp3` (EBS) | `managed-premium` (Azure Disk) | `pd-ssd` (Persistent Disk) |
| Spot instances | SPOT capacity type | Azure Spot | `spot = true` |

## Environments

| File | Purpose |
|------|---------|
| `environments/dev.tfvars` | Zonal cluster, 1 node, no WAF |
| `environments/prod.tfvars` | Regional cluster, 4 nodes, Cloud Armor WAF |
