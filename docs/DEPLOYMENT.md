# Deployment Guide - VisionOps

> Step-by-step instructions for every environment.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| kubectl | 1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.12+ | https://helm.sh/docs/intro/install/ |
| Helmfile | 0.157+ | https://helmfile.readthedocs.io/ |
| gcloud CLI | latest | https://cloud.google.com/sdk/docs/install |
| Terraform | 1.6+ | https://developer.hashicorp.com/terraform/install |

---

## Option 1: GKE (Active — Primary)

### Step 1: Provision cluster (if not already running)

```bash
cd terraform/gcp

# One-time: create Terraform state bucket
gcloud storage buckets create gs://vision-terraform-state-gcp \
  --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://vision-terraform-state-gcp --versioning

# Edit environments/dev.tfvars — set your project_id
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
# Wait ~10-12 minutes
```

### Step 2: Connect kubectl

```bash
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a --project YOUR_PROJECT_ID
kubectl get nodes   # should show 2x e2-standard-4
```

### Step 3: Create namespaces and secrets

```bash
# Create namespaces
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl create namespace ingress-nginx

# Copy the example secret template and fill in your values
cp k8s/secrets-dev.yaml.example k8s/secrets-dev.yaml
# Edit k8s/secrets-dev.yaml — set actual passwords (including Postgres credentials)
kubectl apply -f k8s/secrets-dev.yaml

# Verify secrets exist in both namespaces
kubectl get secrets -n vision-infra
kubectl get secrets -n vision-app
```

**Required secrets** (see `k8s/secrets-dev.yaml.example`):
- `vision-redis-credentials` in `vision-infra` and `vision-app` (key: `password`)
- `vision-minio-credentials` in `vision-infra` and `vision-app` (keys: `rootUser`, `rootPassword`)
- `vision-grafana-credentials` in `vision-monitoring` (keys: `admin-user`, `admin-password`)
- `vision-postgres-credentials` in `vision-app` (keys: `username`, `password`)  
  *this is used by the API once the Postgres release is enabled*
- `vision-jwt-secret` in `vision-app` (key: `key`)  
  *JWT signing secret, set to a strong random value in production*

### Step 4: Deploy all 6 releases

# (Optional) Once Postgres is running you can apply database migrations from the API package:
# cd api && alembic upgrade head  # requires env vars or .env pointing at the cluster database


```bash
cd /path/to/vision
helmfile -e dev sync

# Watch pods  
kubectl get pods -A -w
# Wait for all pods to be Running/Ready (model download ~2-5 min)
```

### Step 5: Get external IP and access

```bash
# Wait for ingress-nginx to get an IP (~1-2 min)
kubectl get svc -n ingress-nginx ingress-nginx-controller -w

# Once EXTERNAL-IP is assigned:
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Frontend:  http://$EXTERNAL_IP/"
echo "API Docs:  http://$EXTERNAL_IP/api/docs"
echo "Health:    http://$EXTERNAL_IP/api/health"
```

### Step 6: Access monitoring

```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n vision-monitoring
# Open http://localhost:3000
# Credentials: from vision-grafana-credentials secret
```

### Updating after a code push (CI builds new image)

```bash
# After GitHub Actions CI completes and pushes new image:
kubectl rollout restart deployment/vision-api -n vision-app
kubectl rollout restart deployment/vision-frontend -n vision-app
kubectl rollout status deployment/vision-api -n vision-app
kubectl rollout status deployment/vision-frontend -n vision-app
```

### Tear down (stop GKE costs)

```bash
# Destroy Helm releases first
helmfile -e dev destroy

# Then destroy cluster
cd terraform/gcp
terraform destroy -var-file=environments/dev.tfvars
```

---

## Option 2: Docker Compose (Local Dev)

**Best for**: Fast iteration, API development without Kubernetes.

```bash
# 1. Start Minikube for infrastructure (Redis + MinIO)
minikube start --cpus=4 --memory=8192
kubectl apply -f k8s/secrets-local.yaml  # create secrets
helmfile -e local apply

# Wait for infra pods
kubectl wait --for=condition=ready pod --all -n vision-infra --timeout=5m

# 2. Port-forward services to localhost
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &
kubectl port-forward -n vision-infra svc/minio 9000:9000 &# (optional) if you want to exercise the database you can port-forward postgres:
# kubectl port-forward -n vision-infra svc/postgres 5432:5432 &
# 3. Start application
docker-compose up -d

# Access
# http://localhost         → Frontend
# http://localhost:8000/docs → API Docs (direct, no nginx proxy)
```

---

## Option 3: Pure Kubernetes (Minikube)

```bash
# 1. Start Minikube (with ingress addon for local ingress)
minikube start --cpus=4 --memory=8192
minikube addons enable ingress

# 2. Create secrets
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl apply -f k8s/secrets-local.yaml

# 3. Deploy
helmfile -e local sync
# Note: ingress-nginx release has installed=false for local env
# Use port-forward instead:
kubectl port-forward svc/vision-frontend 8080:80 -n vision-app

# Open http://localhost:8080
```

---

## Option 4: Python Dev Server (Fastest Iteration)

```bash
cd api
python -m venv venv
.\venv\Scripts\Activate.ps1     # Windows
# source venv/bin/activate       # macOS/Linux
pip install -r requirements-cpu.txt

# Create .env with Minikube port-forward addresses
cat > .env << EOF
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=your_minio_user
MINIO_SECRET_KEY=your_minio_password
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=visiondb
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_postgres_password
JWT_SECRET_KEY=your_jwt_secret_here
ROOT_PATH=
LOG_LEVEL=DEBUG
EOF

# Start infra port-forwards (Minikube must be running with secrets applied)
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &
kubectl port-forward -n vision-infra svc/minio 9000:9000 &

# Run API with hot-reload
uvicorn main:app --reload --host 0.0.0.0 --port 8000
# http://localhost:8000/docs
```

---

## Option 5: AWS EKS (IaC Ready, Not Yet Provisioned)

> Terraform IaC is complete in `terraform/aws/`.

```bash
cd terraform/aws

# Create S3 state backend
aws s3 mb s3://vision-terraform-state --region us-east-1
aws dynamodb create-table --table-name vision-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

terraform init
terraform apply -var-file=environments/dev.tfvars
# ~15-20 minutes

aws eks update-kubeconfig --region us-east-1 --name vision-dev

# Create secrets (use strong random values for cloud)
# ... (same structure as dev, see k8s/secrets-dev.yaml.example)

helmfile -e dev sync
```

**Estimated cost**: ~$300-500/month (dev). Destroy when not in use.

---

## Option 6: Azure AKS (IaC Ready, Not Yet Provisioned)

> Terraform IaC is complete in `terraform/azure/`.

```bash
cd terraform/azure
# Edit environments/dev.tfvars — set subscription_id

az login
az group create --name vision-terraform-state --location eastus
az storage account create --name visionterraformstate \
  --resource-group vision-terraform-state --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name visionterraformstate

terraform init
terraform apply -var-file=environments/dev.tfvars
# ~10-15 minutes

az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks

helmfile -e dev sync
```

**Estimated cost**: ~$300-400/month (dev). Destroy when not in use.

---

## Rollback

```bash
# Check Helm release history
helm history vision-api -n vision-app
helm history vision-frontend -n vision-app

# Rollback to previous release
helm rollback vision-api -n vision-app
helm rollback vision-frontend -n vision-app

# Or force re-deploy from Helmfile (uses images from values)
helmfile -e dev apply
```

---

## Deployment Checklist

- [ ] All namespaces created
- [ ] All secrets applied (check both vision-infra and vision-app namespaces)
- [ ] `helmfile -e dev sync` completes with no errors
- [ ] All pods Running: `kubectl get pods -A`
- [ ] External IP provisioned: `kubectl get svc -n ingress-nginx`
- [ ] Health check passes: `curl http://<IP>/api/health`
- [ ] Swagger UI loads: `http://<IP>/api/docs`
- [ ] Image detection works via UI
- [ ] Grafana accessible via port-forward
