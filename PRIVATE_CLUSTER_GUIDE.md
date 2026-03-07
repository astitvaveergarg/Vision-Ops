# VisionOps — Private Cluster Access Guide

How to access Kubernetes clusters whose API endpoints are private
(not reachable from the public internet).

---

## Overview

| Provider | Dev API Endpoint | Access Method |
|----------|-----------------|---------------|
| GCP GKE (active) | Public endpoint + gcloud auth | `gcloud` direct, no VPN needed |
| GCP GKE prod | Private endpoint | IAP Tunnel or Bastion |
| AWS EKS dev/prod | Private endpoint | Client VPN or Bastion EC2 |
| Azure AKS dev/prod | Private endpoint | VPN Gateway or Azure Bastion |
| Minikube | Local VM | Direct (no restriction) |

---

## GCP GKE — Active Deployment

### Dev Cluster (Public Endpoint — No VPN Required)

The `vision-dev-gke` cluster uses a **public API endpoint** with gcloud IAM authentication.

```bash
# Authenticate
gcloud auth login
gcloud auth application-default login

# Configure kubectl
gcloud container clusters get-credentials vision-dev-gke \
  --zone us-central1-a \
  --project <your-gcp-project-id>

# Verify
kubectl get nodes
kubectl get pods -A
```

Optional: store KUBECONFIG per cluster to avoid conflicts.

```bash
export KUBECONFIG=~/.kube/config-gke-dev
gcloud container clusters get-credentials vision-dev-gke \
  --zone us-central1-a --project <project-id>
kubectl get nodes
```

### Prod Cluster (Private Endpoint)

```bash
# Option 1: Cloud IAP Tunnel (recommended — no infrastructure needed)
gcloud container clusters get-credentials vision-prod-gke \
  --zone us-central1-a --project <project-id> \
  --internal-ip

# Tunnel the local kubectl traffic through IAP
kubectl proxy &

# Option 2: Bastion VM in the same VPC
gcloud compute ssh bastion-vm --zone us-central1-a --project <project-id>
# From inside: gcloud container clusters get-credentials ...
```

### Port-Forwarding Services (GKE)

```bash
# API
kubectl port-forward -n vision-app svc/vision-api 8000:8000
curl http://localhost:8000/health

# Grafana
kubectl port-forward -n vision-monitoring svc/vision-prometheus-grafana 3000:80
# Open http://localhost:3000

# MinIO Console
kubectl port-forward -n vision-infra svc/vision-minio 9001:9001
# Open http://localhost:9001
```

---

## AWS EKS

### Dev / Prod (Private API Endpoint)

All EKS clusters are provisioned with `endpoint_public_access = false`.
You **cannot** run `kubectl` from your laptop directly.

### Option 1: Bastion EC2 Host (Quickest — 30 min)

```bash
# Launch a small EC2 instance in the same VPC public subnet
# Instance type: t3.micro, Amazon Linux 2, same VPC as EKS

# SSH
ssh -i ~/.ssh/key.pem ec2-user@<bastion-public-ip>

# On bastion: install kubectl + aws CLI, then:
aws eks update-kubeconfig --region us-east-1 --name vision-dev
kubectl get nodes
```

### Option 2: AWS Client VPN (~2 hours setup)

```bash
# Follow: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/
# Provision Client VPN Endpoint in same VPC, associate with private subnet
# Download .ovpn config, connect from laptop
# Once connected: aws eks update-kubeconfig ... works directly
```

### Port-Forwarding (from bastion or via VPN)

```bash
kubectl port-forward -n vision-app svc/vision-api 8000:8000 &
kubectl port-forward -n vision-monitoring svc/vision-prometheus-grafana 3000:80 &
```

---

## Azure AKS

### Dev / Prod (Private API Server)

AKS clusters are provisioned with `private_cluster_enabled = true`.

### Option 1: Azure Cloud Shell (Immediate — no setup)

```bash
# Open https://shell.azure.com
# Already has az CLI, kubectl
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
kubectl get nodes
```

### Option 2: Azure Bastion

```bash
# Deploy Azure Bastion in the same VNet
# Connect to a Linux VM in the VNet via browser, no public IP needed
# From VM: az aks get-credentials ...
```

### Option 3: Point-to-Site VPN (~2 hours)

```bash
# Create VPN Gateway, download VPN client cert
# Connect → your laptop is on the VNet → kubectl works directly
```

### Port-Forwarding (from Bastion VM or P2S VPN)

```bash
kubectl port-forward -n vision-app svc/vision-api 8000:8000 &
kubectl port-forward -n vision-monitoring svc/vision-prometheus-grafana 3000:80 &
```

---

## Minikube (Local)

No access restrictions. Start and use directly:

```bash
minikube start --cpus=4 --memory=8192
helmfile -e local sync
minikube service ingress-nginx-controller -n ingress-nginx --url
```

---

## Summary — Quickest Path to Each Cluster

| Target | Quickest Method | Time |
|--------|-----------------|------|
| GKE dev | `gcloud auth login` + `get-credentials` | 2 min |
| GKE prod | Cloud IAP tunnel or bastion | 20-30 min |
| EKS dev/prod | Bastion EC2 in public subnet | 30 min |
| AKS dev/prod | Azure Cloud Shell | 0 min |
| Minikube | `minikube start` | 5 min |
