# 🚀 VisionOps Deployment Guide

> **Step-by-step deployment instructions** - From local development to production cloud deployment

---

## 📑 Table of Contents

- [Prerequisites](#prerequisites)
- [Local Development Setup](#local-development-setup)
- [Minikube Deployment](#minikube-deployment)
- [Cloud Development Cluster](#cloud-development-cluster)
- [Production Deployment](#production-deployment)
- [Post-Deployment](#post-deployment)
- [Rollback Procedures](#rollback-procedures)
- [Upgrade Procedures](#upgrade-procedures)

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **Docker** | 20.10+ | Container runtime | [Get Docker](https://docs.docker.com/get-docker/) |
| **kubectl** | 1.28+ | Kubernetes CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | 3.12+ | Package manager | [Install Helm](https://helm.sh/docs/intro/install/) |
| **Helmfile** | 0.157+ | Multi-chart orchestration | [Install Helmfile](https://helmfile.readthedocs.io/) |
| **Minikube** | 1.31+ | Local K8s | [Install Minikube](https://minikube.sigs.k8s.io/docs/start/) |
| **Terraform** | 1.6+ | Infrastructure as code | [Install Terraform](https://developer.hashicorp.com/terraform/install) |

### Cloud Prerequisites (for production)

**AWS**:
- AWS CLI configured (`aws configure`)
- IAM permissions for EKS, VPC, CloudFront, S3
- S3 bucket for Terraform state

**Azure**:
- Azure CLI installed (`az login`)
- Subscription access for AKS, VNet, Front Door
- Storage account for Terraform state

### System Requirements

**Local Development**:
- CPU: 4 cores minimum
- RAM: 8GB minimum (16GB recommended)
- Disk: 50GB free space
- OS: Windows 10+, macOS 12+, Linux (Ubuntu 20.04+)

---

## Local Development Setup

### Option 1: Docker Compose (Fastest)

**Best for**: Quick testing, API development

#### Step 1: Start Infrastructure

```bash
# Clone repository
git clone https://github.com/astitvaveergarg/Vision-AI.git
cd Vision-AI

# Start Minikube
minikube start --cpus=4 --memory=8192 --disk-size=50g

# Deploy infrastructure (Redis, MinIO, Monitoring)
helmfile -e local apply

# Wait for pods to be ready
kubectl wait --for=condition=ready pod --all -n vision-infra --timeout=5m
kubectl wait --for=condition=ready pod --all -n vision-monitoring --timeout=5m
```

#### Step 2: Port-Forward Services

```bash
# Redis
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &

# MinIO
kubectl port-forward -n vision-infra svc/minio 9000:9000 &
```

#### Step 3: Start Application

```bash
# Launch Docker Compose stack
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

#### Step 4: Access Application

```
Frontend: http://localhost
API Docs: http://localhost:8000/docs
```

#### Step 5: Test Detection

```bash
# Upload test image
curl -X POST http://localhost:8000/detect \
  -F "file=@test.jpg" \
  -F "model=yolov8n"
```

#### Cleanup

```bash
# Stop Docker Compose
docker-compose down

# Stop port-forwards
pkill -f "port-forward"

# Delete Minikube (optional)
minikube delete
```

---

### Option 2: Pure Python (Development)

**Best for**: API development without Docker

#### Step 1: Setup Python Environment

```bash
# Create virtual environment
cd api
python -m venv venv

# Activate (Windows)
.\venv\Scripts\Activate.ps1

# Activate (macOS/Linux)
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

#### Step 2: Configure Environment

```bash
# Create .env file
cat > .env << EOF
REDIS_HOST=localhost
REDIS_PORT=6379
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
LOG_LEVEL=DEBUG
EOF
```

#### Step 3: Start Services (from Minikube)

```bash
# Same as Option 1, Step 1 & 2
minikube start --cpus=4 --memory=8192
helmfile -e local apply
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &
kubectl port-forward -n vision-infra svc/minio 9000:9000 &
```

#### Step 4: Run API Locally

```bash
# From api/ directory
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

#### Step 5: Serve Frontend (Optional)

```bash
# Install nginx (Windows: via Chocolatey)
choco install nginx

# Copy frontend files
cp -r frontend/* C:/tools/nginx/html/

# Edit C:/tools/nginx/conf/nginx.conf
# Change proxy_pass to http://localhost:8000

# Start nginx
nginx
```

---

## Minikube Deployment

**Best for**: Testing Kubernetes deployment locally

### Step 1: Prerequisites

```bash
# Verify tools
minikube version
kubectl version --client
helm version
helmfile version
```

### Step 2: Create Kubernetes Secrets

```bash
# Create namespaces
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring

# MinIO credentials
kubectl create secret generic minio-credentials \
  --from-literal=access-key=minioadmin \
  --from-literal=secret-key=minioadmin \
  -n vision-infra

# Redis credentials
kubectl create secret generic redis-credentials \
  --from-literal=password=redis123 \
  -n vision-infra
```

### Step 3: Deploy Complete Stack

```bash
# Deploy infrastructure + monitoring + application
helmfile -e local apply

# This deploys:
# - Redis (master + replicas)
# - MinIO (standalone)
# - Prometheus + Grafana
# - VisionOps API
```

### Step 4: Wait for Rollout

```bash
# Wait for all pods
kubectl wait --for=condition=ready pod --all -n vision-infra --timeout=10m
kubectl wait --for=condition=ready pod --all -n vision-app --timeout=10m
kubectl wait --for=condition=ready pod --all -n vision-monitoring --timeout=10m

# Check status
kubectl get pods -A
```

### Step 5: Access Services

**Option A: NodePort (Recommended)**

```bash
# Get URLs
minikube service vision-api -n vision-app --url
# Example output: http://192.168.49.2:30080

# Access API
curl http://192.168.49.2:30080/health
```

**Option B: Port-Forward**

```bash
# Forward API
kubectl port-forward -n vision-app svc/vision-api 8000:8000 &

# Forward Grafana
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80 &

# Access
curl http://localhost:8000/health
# Grafana: http://localhost:3000 (admin/prom-operator)
```

### Step 6: Test Auto-Scaling

```bash
# Generate load
for i in {1..100}; do
  curl -s -X POST http://localhost:8000/detect \
    -F "file=@test.jpg" &
done

# Watch HPA scale
kubectl get hpa -n vision-app -w

# Expected: Replicas increase from 1 to 2-3
```

### Step 7: View Metrics

```bash
# Port-forward Grafana
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Open: http://localhost:3000
# Login: admin / prom-operator
# Dashboard: "Vision API Performance"
```

### Cleanup

```bash
# Delete all releases
helmfile -e local destroy

# Or selectively
helmfile -e local -l name=vision-api destroy

# Delete Minikube (full reset)
minikube delete
```

---

## Cloud Development Cluster

**Best for**: Testing production configuration before going live

### AWS EKS Deployment

#### Step 1: Configure Terraform Backend

```bash
# Create S3 bucket for state
aws s3 mb s3://vision-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket vision-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name vision-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

#### Step 2: Provision Infrastructure

```bash
cd terraform/aws

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment (review changes)
terraform plan -var-file=environments/dev.tfvars

# Apply (provision EKS cluster)
terraform apply -var-file=environments/dev.tfvars
# ⏱️ Wait 15-20 minutes
```

#### Step 3: Configure kubectl

```bash
# Get cluster credentials
aws eks update-kubeconfig --region us-east-1 --name vision-dev

# Verify connection
kubectl get nodes
# Should show 2-3 nodes
```

#### Step 4: Setup Access (Private Cluster)

**Option A: Bastion Host (Quick)**

```bash
# Launch EC2 instance in public subnet
# SSH into bastion
# From bastion, kubectl works directly
```

**Option B: VPN (Recommended)**

See: [PRIVATE_CLUSTER_GUIDE.md](../PRIVATE_CLUSTER_GUIDE.md) for detailed VPN setup

#### Step 5: Install Post-Deployment Components

```bash
# ALB Ingress Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=vision-dev \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw alb_controller_role_arn)

# EBS CSI Driver (if not enabled via Terraform)
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system
```

#### Step 6: Create Secrets

```bash
# Generate strong credentials
MINIO_ACCESS_KEY=$(openssl rand -base64 32)
MINIO_SECRET_KEY=$(openssl rand -base64 48)
REDIS_PASSWORD=$(openssl rand -base64 32)

# Create secrets
kubectl create namespace vision-infra
kubectl create namespace vision-app

kubectl create secret generic minio-credentials \
  --from-literal=access-key=$MINIO_ACCESS_KEY \
  --from-literal=secret-key=$MINIO_SECRET_KEY \
  -n vision-infra

kubectl create secret generic redis-credentials \
  --from-literal=password=$REDIS_PASSWORD \
  -n vision-infra

# Save credentials securely!
echo "MinIO Access Key: $MINIO_ACCESS_KEY" >> credentials.txt
echo "MinIO Secret Key: $MINIO_SECRET_KEY" >> credentials.txt
echo "Redis Password: $REDIS_PASSWORD" >> credentials.txt
```

#### Step 7: Deploy Application

```bash
# From project root
helmfile -e dev apply

# Wait for rollout
kubectl rollout status deployment/vision-api -n vision-app

# Check pods
kubectl get pods -n vision-app
```

#### Step 8: Verify Deployment

```bash
# Port-forward (since it's private)
kubectl port-forward -n vision-app svc/vision-api 8000:8000

# Test health
curl http://localhost:8000/health

# Test detection
curl -X POST http://localhost:8000/detect \
  -F "file=@test.jpg" \
  -F "model=yolov8n"
```

#### Cleanup (Dev Cluster)

```bash
# Delete application
helmfile -e dev destroy

# Destroy infrastructure
cd terraform/aws
terraform destroy -var-file=environments/dev.tfvars

# ⚠️ This will:
# - Delete EKS cluster
# - Delete VPC and networking
# - Release all resources
# - CANNOT BE UNDONE
```

**Cost**: ~$300-500/month (destroy when not in use!)

---

### Azure AKS Deployment

#### Step 1: Configure Terraform Backend

```bash
# Login to Azure
az login

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

#### Step 2: Update Variables

```bash
cd terraform/azure

# Edit environments/dev.tfvars
# Update: subscription_id = "your-actual-subscription-id"

# Get subscription ID
az account show --query id -o tsv
```

#### Step 3: Provision Infrastructure

```bash
# Initialize
terraform init

# Validate
terraform validate

# Plan
terraform plan -var-file=environments/dev.tfvars

# Apply
terraform apply -var-file=environments/dev.tfvars
# ⏱️ Wait 10-15 minutes
```

#### Step 4: Configure kubectl

```bash
# Get cluster credentials
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks

# Verify
kubectl get nodes
```

#### Step 5: Install Post-Deployment Components

```bash
# NGINX Ingress Controller (for internal LB)
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"="true"
```

#### Step 6-8: Same as AWS

Follow AWS steps 6-8 (secrets, deploy, verify)

#### Cleanup

```bash
helmfile -e dev destroy
cd terraform/azure
terraform destroy -var-file=environments/dev.tfvars
```

**Cost**: ~$400-550/month

---

## Production Deployment

**⚠️ WARNING**: Production deployment is **permanent** and **costly**. Only proceed after thorough dev testing.

### Pre-Flight Checklist

- [ ] Dev deployment tested successfully
- [ ] Load testing completed (k6/Locust)
- [ ] Security audit passed
- [ ] Backup strategy defined
- [ ] Monitoring dashboards configured
- [ ] On-call rotation established
- [ ] Rollback plan documented
- [ ] Budget approved (~$1,500-2,500/month)

### Production Deployment Steps

#### Step 1: Provision Infrastructure

```bash
# AWS
cd terraform/aws
terraform apply -var-file=environments/prod.tfvars

# Azure
cd terraform/azure
terraform apply -var-file=environments/prod.tfvars

# ⏱️ Wait 20-25 minutes (larger cluster)
```

#### Step 2: Configure CDN

**AWS CloudFront**:

```bash
# Get CDN domain
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
echo "CloudFront Domain: $CLOUDFRONT_DOMAIN"

# Get custom header secret
CDN_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id vision-prod-cdn-secret \
  --query SecretString --output text)

# Create K8s secret
kubectl create secret generic cdn-secret \
  --from-literal=CDN_SECRET=$CDN_SECRET \
  -n vision-app
```

**Azure Front Door**:

```bash
# Get Front Door domain
FRONTDOOR_DOMAIN=$(terraform output -raw frontdoor_endpoint_hostname)
echo "Front Door Domain: $FRONTDOOR_DOMAIN"
```

#### Step 3: Setup Custom Domain (Optional)

```bash
# Create DNS CNAME record
# Name: api.yourdomain.com
# Value: <cloudfront-domain> or <frontdoor-domain>

# Wait for DNS propagation (5-30 minutes)
nslookup api.yourdomain.com

# Request SSL certificate (AWS ACM / Azure managed)
# CloudFront will auto-provision if ACM cert exists
```

#### Step 4: Deploy Application

```bash
# Create production secrets (STRONG passwords!)
MINIO_ACCESS_KEY=$(openssl rand -base64 48)
MINIO_SECRET_KEY=$(openssl rand -base64 64)
REDIS_PASSWORD=$(openssl rand -base64 48)

kubectl create secret generic minio-credentials \
  --from-literal=access-key=$MINIO_ACCESS_KEY \
  --from-literal=secret-key=$MINIO_SECRET_KEY \
  -n vision-infra

kubectl create secret generic redis-credentials \
  --from-literal=password=$REDIS_PASSWORD \
  -n vision-infra

# Deploy
helmfile -e prod apply

# Verify
kubectl get pods -A
kubectl get hpa -n vision-app  # Should show min 3 replicas
```

#### Step 5: Validate CDN Access

```bash
# Test public access (via CDN)
curl https://$CLOUDFRONT_DOMAIN/health
# or
curl https://$FRONTDOOR_DOMAIN/health

# Should return: {"status": "healthy"}

# Test direct ALB access (should FAIL)
ALB_URL=$(kubectl get ingress -n vision-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://$ALB_URL/health
# Should return: 403 Forbidden (custom header missing)
```

#### Step 6: Configure Monitoring

```bash
# Port-forward Grafana
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Import dashboards (if not auto-imported)
# - Kubernetes Cluster Overview (ID: 7249)
# - NGINX Ingress Controller (ID: 9614)
# - Redis (ID: 11835)

# Configure AlertManager
kubectl edit configmap -n vision-monitoring prometheus-alertmanager

# Add alert destinations (Slack, email, PagerDuty)
```

#### Step 7: Load Testing

```bash
# Install k6 (if not installed)
choco install k6  # Windows
brew install k6   # macOS

# Run load test
k6 run tests/load/test_api.js

# Watch auto-scaling
kubectl get hpa -n vision-app -w

# Expected behavior:
# - Starts at 3 pods (minReplicas)
# - Scales to 10-15 pods under load
# - Scales down after 5 minutes of low traffic
```

---

## Post-Deployment

### Smoke Tests

```bash
# Health check
curl https://api.yourdomain.com/health

# Detection test
curl -X POST https://api.yourdomain.com/detect \
  -F "file=@test.jpg" | jq '.'

# Metrics scraping
curl https://api.yourdomain.com/metrics | grep http_requests_total
```

### Monitoring Setup

1. **Configure Alerts**:
   - High error rate (>5%)
   - High latency (p95 > 2s)
   - Pod crashes
   - Resource exhaustion

2. **Test Alerts**:
   ```bash
   # Kill a pod (should trigger alert)
   kubectl delete pod -n vision-app -l app=vision-api --force
   
   # Verify alert fires and auto-remediation works
   ```

3. **Dashboard Verification**:
   - Request rate graph shows data
   - Latency histogram populated
   - Pod count matches HPA settings
   - Cache hit ratio visible

### Backup Configuration

```bash
# Redis snapshots (already configured in Helm)
# MinIO: Enable versioning
kubectl exec -n vision-infra deployment/minio -- \
  mc version enable minio/vision-uploads

# Kubernetes manifests backup
kubectl get all -n vision-app -o yaml > backup-vision-app.yaml
kubectl get all -n vision-infra -o yaml > backup-vision-infra.yaml
```

---

## Rollback Procedures

### Rollback Application Deployment

```bash
# Check deployment history
kubectl rollout history deployment/vision-api -n vision-app

# Rollback to previous version
kubectl rollout undo deployment/vision-api -n vision-app

# Rollback to specific revision
kubectl rollout undo deployment/vision-api -n vision-app --to-revision=2

# Verify rollback
kubectl rollout status deployment/vision-api -n vision-app
```

### Rollback Helm Release

```bash
# List release history
helm history vision-api -n vision-app

# Rollback to previous release
helm rollback vision-api -n vision-app

# Rollback to specific revision
helm rollback vision-api 2 -n vision-app
```

### Rollback Infrastructure Changes

```bash
# Terraform rollback
cd terraform/aws  # or terraform/azure

# Checkout previous version from git
git log --oneline terraform/  # Find last good commit
git checkout <commit-hash> terraform/

# Apply previous state
terraform apply -var-file=environments/prod.tfvars

# ⚠️ BE CAREFUL: This can cause downtime
```

---

## Upgrade Procedures

### Upgrade Application Version

```bash
# Build new image
docker build -t astitvaveergarg/vision-api:v1.1.0 -f docker/Dockerfile .
docker push astitvaveergarg/vision-api:v1.1.0

# Update Helm values
# charts/api/values-prod.yaml
# image:
#   tag: v1.1.0

# Deploy with canary (optional)
# See: helm-canary.yaml for advanced patterns

# Rolling update
helm upgrade vision-api charts/api -n vision-app -f charts/api/values-prod.yaml

# Watch rollout
kubectl rollout status deployment/vision-api -n vision-app

# Verify
kubectl get pods -n vision-app -o wide
```

### Upgrade Kubernetes Version

```bash
# AWS EKS
aws eks update-cluster-version --name vision-prod --kubernetes-version 1.29

# Azure AKS
az aks upgrade --resource-group vision-prod-rg --name vision-prod-aks --kubernetes-version 1.29

# Update node groups (one at a time)
# EKS: Terraform apply with updated version
# AKS: az aks nodepool upgrade
```

### Upgrade Dependencies

```bash
# Redis
helm upgrade redis bitnami/redis -n vision-infra -f charts/infrastructure/redis/values.yaml

# MinIO
helm upgrade minio bitnami/minio -n vision-infra -f charts/infrastructure/minio/values.yaml

# Prometheus
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n vision-monitoring -f charts/infrastructure/monitoring/values.yaml
```

---

## Troubleshooting During Deployment

See: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for comprehensive troubleshooting guide

### Common Deployment Issues

**Pods Stuck in Pending**:
```bash
kubectl describe pod <pod-name> -n vision-app
# Check: Insufficient resources, PVC not bound, node selector mismatch
```

**ImagePullBackOff**:
```bash
# For Minikube: Load image manually
minikube image load astitvaveergarg/vision-api:latest

# For cloud: Verify image exists on Docker Hub
docker pull astitvaveergarg/vision-api:latest
```

**CrashLoopBackOff**:
```bash
# Check logs
kubectl logs <pod-name> -n vision-app --previous

# Common causes:
# - Missing environment variables
# - Can't connect to Redis/MinIO
# - Model download failed
```

---

## Cost Management

### Cost Monitoring

**AWS**:
```bash
# Enable Cost Explorer
# Tag all resources with: Environment=prod, Project=VisionOps

# View costs
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Environment
```

**Azure**:
```bash
# Cost analysis in Azure Portal
# Subscriptions → Cost Analysis → Group by: Tag
```

### Cost Optimization Tips

1. **Use Spot/Low Priority Nodes**: 60-80% cost reduction for non-critical workloads
2. **Right-size Nodes**: Use c5.xlarge instead of c5.2xlarge if CPU <50%
3. **Scale Down Dev**: Reduce dev cluster to 1-2 nodes when not in use
4. **Reserved Instances**: 40% discount for 1-year commitment (prod only)
5. **Delete Unused Resources**: Old snapshots, unused volumes, stale images

---

## Security Hardening

### Post-Deployment Security

1. **Enable Audit Logging**:
   ```bash
   # AWS CloudTrail, Azure Activity Log
   # Monitor all kubectl commands
   ```

2. **Configure Network Policies**:
   ```bash
   kubectl apply -f charts/api/templates/networkpolicy.yaml
   ```

3. **Enable Pod Security Policies**:
   ```bash
   # Restrict privileged containers, hostPath, etc.
   ```

4. **Rotate Secrets**:
   ```bash
   # Rotate every 90 days
   # Use AWS Secrets Manager / Azure Key Vault for automation
   ```

5. **Enable WAF Logging**:
   ```bash
   # CloudWatch Logs (AWS) / Azure Monitor
   # Analyze blocked requests
   ```

---

## Maintenance Windows

**Recommended Schedule**:
- **Patch Updates**: Weekly (Sundays 2-4 AM UTC)
- **Minor Upgrades**: Monthly (First Sunday)
- **Major Upgrades**: Quarterly (Planned downtime)

**Notification Protocol**:
1. Announce 7 days before
2. Send reminder 24 hours before
3. Post status updates during maintenance
4. Confirm completion

---

## Support & Documentation

- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **API Reference**: [API.md](API.md)
- **Troubleshooting**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Private Cluster Access**: [PRIVATE_CLUSTER_GUIDE.md](../PRIVATE_CLUSTER_GUIDE.md)

---

**Last Updated**: February 13, 2026  
**Author**: Astitva Veer Garg
