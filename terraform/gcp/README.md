# Terraform - GCP GKE (Active Deployment)

> ✅ **This is the active cloud deployment.** Cluster `vision-dev-gke` is provisioned in `us-central1-a`.

Provisions a private GKE cluster for VisionOps on Google Cloud Platform.

---

## Architecture

```
GCP Project
└── VPC Network (10.0.0.0/16)
    └── Subnetwork (10.0.1.0/24)
        └── GKE Private Cluster: vision-dev-gke
            ├── General Node Pool  (e2-standard-4, 1-3 nodes)
            │   └── Redis, MinIO, Prometheus, Frontend
            └── ML Node Pool       (e2-standard-4, 0-2 nodes)
                └── vision-api (YOLO inference)
        └── Cloud NAT (outbound internet — model downloads)
        └── Cloud Armor WAF (prod only)

Budget Enforcer Cloud Function
└── Pub/Sub trigger on billing alerts → disables billing to stop costs
```

---

## Cost Estimates

| Environment | Config | Cost/hr | Cost/day |
|-------------|--------|---------|---------|
| **Dev (active)** | 2x e2-standard-4, zonal | ~$0.27 | ~$6.50 |
| Prod | 4x e2-standard-4 (2 pools), regional | ~$0.54 | ~$13.00 |

**GKE zonal control plane is FREE.**  
Destroy the cluster between testing sessions to minimise cost.

With Google Cloud $300 free credit at ~$0.27/hr active usage (e.g. 4 hrs/day):
- Dev testing → credit lasts ~278 days

---

## Files

```
terraform/gcp/
├── main.tf               # Provider, backend (GCS), APIs
├── variables.tf          # Input variables
├── outputs.tf            # kubectl configure command, cluster name/endpoint
├── gke.tf                # GKE cluster + node pools (general + ml)
├── billing.tf            # Budget alerts via Pub/Sub
├── cloud_armor.tf        # WAF security policy (prod only)
├── budget_enforcer.tf    # Cloud Function: auto-disable billing on overspend
├── environments/
│   ├── dev.tfvars        # project_id, cluster_name, zone, node counts
│   └── prod.tfvars       # regional cluster, larger node pools
└── functions/
    └── budget_enforcer/  # Python Cloud Function source
```

---

## One-Time Setup

### 1. Authenticate gcloud

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Create Terraform state bucket

```bash
gcloud storage buckets create gs://vision-terraform-state-gcp \
  --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://vision-terraform-state-gcp --versioning
```

### 3. Set your project ID

Edit `environments/dev.tfvars`:
```hcl
project_id = "your-actual-project-id"   # ← required
```

---

## Deploy Dev Cluster

```bash
cd terraform/gcp

terraform init
terraform validate
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
# ~10-12 minutes

# Connect kubectl
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a --project YOUR_PROJECT_ID
kubectl get nodes   # 2x e2-standard-4
```

---

## Deploy VisionOps to GKE

```bash
cd /path/to/vision   # project root

# Create namespaces
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl create namespace ingress-nginx

# Apply secrets (copy example, fill in values)
cp k8s/secrets-dev.yaml.example k8s/secrets-dev.yaml
# Edit k8s/secrets-dev.yaml with your passwords
kubectl apply -f k8s/secrets-dev.yaml

# Deploy all 6 Helm releases
helmfile -e dev sync

# Wait for pods (model download takes 2-5 min)
kubectl get pods -A -w

# Get external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Test
curl http://<EXTERNAL-IP>/api/health
```

**Required secrets** (both `vision-infra` and `vision-app` namespaces):
- `vision-redis-credentials` — key: `password`
- `vision-minio-credentials` — keys: `rootUser`, `rootPassword`
- `vision-grafana-credentials` in `vision-monitoring` — keys: `admin-user`, `admin-password`

---

## Destroy (Stop Costs)

```bash
# 1. Remove Kubernetes workloads
helmfile -e dev destroy

# 2. Destroy GKE infrastructure
cd terraform/gcp
terraform destroy -var-file=environments/dev.tfvars
# ~5-8 minutes
```

---

## Outputs

```bash
terraform output
# configure_kubectl  — gcloud command to set up kubeconfig
# cluster_name       — GKE cluster name
# cluster_endpoint   — Kubernetes API endpoint
```

---

## Key Differences vs AWS/Azure

| Feature | GCP GKE | AWS EKS | Azure AKS |
|---------|---------|---------|-----------|
| Control plane | Free (zonal) | $0.10/hr | Free |
| kubectl auth | gcloud auth | aws eks update-kubeconfig | az aks get-credentials |
| Ingress | GKE Ingress / NGINX | AWS LB Controller / NGINX | NGINX Ingress |
| WAF | Cloud Armor | CloudFront + WAF | Front Door + WAF |
| Storage class (dev) | `standard` (pd-standard) | `gp3` (EBS) | `managed` (Azure Disk) |
| Storage class (prod) | `premium-rwo` (pd-ssd) | `gp3` (EBS) | `managed-premium` |
| Node internet access | Cloud NAT | NAT Gateway | NAT Gateway |
