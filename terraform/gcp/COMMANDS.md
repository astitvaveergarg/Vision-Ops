# Quick Reference - GCP GKE Terraform Commands

## Prerequisites (One-Time)

# 1. Install gcloud CLI
# https://cloud.google.com/sdk/docs/install

# 2. Authenticate
gcloud auth login
gcloud auth application-default login

# 3. Set your project
gcloud config set project YOUR_PROJECT_ID

# 4. Create GCS backend bucket for Terraform state
gcloud storage buckets create gs://vision-terraform-state-gcp \
  --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://vision-terraform-state-gcp --versioning

# 5. Update project_id in environments/dev.tfvars
# project_id = "your-actual-project-id"

## Development Environment

# Initialize Terraform
cd terraform/gcp
terraform init

# Validate
terraform validate

# Plan
terraform plan -var-file=environments/dev.tfvars

# Apply (~10-12 minutes)
terraform apply -var-file=environments/dev.tfvars

# Configure kubectl
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a \
  --project YOUR_PROJECT_ID

# Verify cluster
kubectl get nodes
kubectl get pods -A

## Deploy VisionOps

# Create secrets
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

# Deploy with Helmfile (from project root)
cd ../..
helmfile -e dev sync

# Watch pods come up
kubectl get pods -A -w

# Access the API (no public IP needed — use port-forward)
kubectl port-forward -n vision-app svc/vision-api 8000:8000
curl http://localhost:8000/health

# Access Grafana
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin)

## Destroy (IMPORTANT: do this to stop costs)
cd terraform/gcp
helmfile -e dev destroy
terraform destroy -var-file=environments/dev.tfvars

## Production Environment

# Plan
terraform plan -var-file=environments/prod.tfvars

# Apply (~15-20 minutes)
terraform apply -var-file=environments/prod.tfvars

# Configure kubectl
gcloud container clusters get-credentials vision-prod-gke \
  --location us-central1 \
  --project YOUR_PROJECT_ID

# Deploy
cd ../..
helmfile -e prod apply

# Destroy prod
terraform destroy -var-file=environments/prod.tfvars

## Useful Commands

# View Terraform outputs
terraform output configure_kubectl
terraform output cluster_name

# GKE cluster info
gcloud container clusters list
gcloud container clusters describe vision-dev-gke --location us-central1-a

# Check node pool status
kubectl get nodes -L role,workload

# Watch HPA scaling
kubectl get hpa -n vision-app -w

# Cost estimate (current usage)
# Dev (1 e2-standard-4 node running): ~$0.16/hr
# Prod (2 general + 2 ml nodes running): ~$0.65/hr
# Remember: GKE zonal control plane is FREE
