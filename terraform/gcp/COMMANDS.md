# Quick Reference - GCP GKE Commands

## Prerequisites (One-Time)

```bash
# Install gcloud CLI: https://cloud.google.com/sdk/docs/install

# Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# Create GCS backend bucket
gcloud storage buckets create gs://vision-terraform-state-gcp \
  --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://vision-terraform-state-gcp --versioning

# Edit project_id in environments/dev.tfvars
```

## Dev Cluster — Provision

```bash
cd terraform/gcp
terraform init
terraform validate
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars   # ~10-12 min

# Connect kubectl
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a --project YOUR_PROJECT_ID
kubectl get nodes
```

## Deploy VisionOps

```bash
# From project root
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl create namespace ingress-nginx

# Create secrets (both namespaces)
cp k8s/secrets-dev.yaml.example k8s/secrets-dev.yaml
# Edit k8s/secrets-dev.yaml with real credentials
kubectl apply -f k8s/secrets-dev.yaml

# Deploy 6 Helm releases
helmfile -e dev sync

# Watch pods (model download ~2-5 min)
kubectl get pods -A -w

# Get external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Test
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/api/health
echo "Swagger UI: http://$EXTERNAL_IP/api/docs"
```

## Monitoring

```bash
# Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n vision-monitoring
# http://localhost:3000  — credentials from vision-grafana-credentials secret

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n vision-monitoring
# http://localhost:9090
```

## Update Application (after CI push)

```bash
kubectl rollout restart deployment/vision-api      -n vision-app
kubectl rollout restart deployment/vision-frontend -n vision-app
kubectl rollout status  deployment/vision-api      -n vision-app
kubectl rollout status  deployment/vision-frontend -n vision-app
```

## Scale / Debug

```bash
# Pod status
kubectl get pods -n vision-app
kubectl describe pod <pod-name> -n vision-app
kubectl logs -f deployment/vision-api -n vision-app

# Resource usage
kubectl top nodes
kubectl top pods -n vision-app

# Shell into API pod
kubectl exec -it deployment/vision-api -n vision-app -- /bin/bash

# Node labels / pool
kubectl get nodes -L role,cloud.google.com/gke-nodepool

# HPA (prod)
kubectl get hpa -n vision-app -w
```

## Destroy (STOP COSTS)

```bash
# Always destroy workloads first
helmfile -e dev destroy

# Then destroy GKE
cd terraform/gcp
terraform destroy -var-file=environments/dev.tfvars   # ~5-8 min
```

## Prod Cluster

```bash
cd terraform/gcp
terraform plan  -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars   # ~15-20 min

gcloud container clusters get-credentials vision-prod-gke \
  --location us-central1 --project YOUR_PROJECT_ID

helmfile -e prod apply

# Destroy prod
terraform destroy -var-file=environments/prod.tfvars
```

## Costs

```
Dev  (2x e2-standard-4, zonal) : ~$0.27/hr  ~$6.50/day
Prod (4x e2-standard-4, regional): ~$0.54/hr ~$13/day
GKE zonal control plane: FREE
```
