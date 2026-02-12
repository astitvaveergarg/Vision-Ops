# VisionOps - ML Inference Platform

Production-ready YOLO object detection API with complete Kubernetes deployment.

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     VisionOps Stack                           │
├──────────────────────────────────────────────────────────────┤
│  Frontend (Nginx)  →  Backend (FastAPI + YOLO)               │
│         ↓                      ↓                              │
│    Redis Cache         MinIO Storage                          │
│         ↓                      ↓                              │
│         Prometheus + Grafana Monitoring                       │
└──────────────────────────────────────────────────────────────┘
```

## ✨ Features

- **Multi-Model Support**: YOLOv8 (nano, small, medium, large, xlarge)
- **Production Ready**: HPA, PDB, NetworkPolicies, Resource Limits
- **Observability**: Prometheus metrics, Grafana dashboards
- **Scalable**: Auto-scaling from 1 to 20 pods based on load
- **Secure**: Non-root containers, secrets management, RBAC
- **Multi-Environment**: Local (Minikube), Dev, Prod configurations

## 📦 Components

| Component | Purpose | Tech Stack |
|-----------|---------|------------|
| **Frontend** | Web UI | Nginx + HTML/JS |
| **Backend** | ML API | FastAPI + YOLOv8 + PyTorch |
| **Cache** | Detection caching | Redis |
| **Storage** | Image persistence | MinIO (S3-compatible) |
| **Monitoring** | Metrics & alerting | Prometheus + Grafana |

## 🚀 Quick Start

### Prerequisites

- **Local**: Minikube, kubectl, helm, helmfile, docker
- **Cloud**: Kubernetes cluster (EKS/GKE/AKS), kubectl, helm, helmfile

### Local Development (Minikube)

```bash
# Start Minikube
minikube start --cpus=4 --memory=8192 --disk-size=50g

# Deploy infrastructure + monitoring
helmfile -e local apply

# Check deployments
kubectl get pods -A

# Port forward to access services
kubectl port-forward -n vision-infra svc/redis-master 6379:6379
kubectl port-forward -n vision-infra svc/minio 9000:9000 9001:9001
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Access Grafana: http://localhost:3000 (admin/prom-operator)
# Access MinIO Console: http://localhost:9001 (minioadmin/minioadmin)
```

### Docker Compose (Testing)

```bash
# Start infrastructure in Minikube first
helmfile -e local apply

# Port forward Redis and MinIO
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &
kubectl port-forward -n vision-infra svc/minio 9000:9000 &

# Start application stack
docker-compose up -d

# Access frontend: http://localhost
# Access API docs: http://localhost:8000/docs
```

## 🌍 Environments

### Local (Minikube)

```bash
helmfile -e local apply
```

- **Purpose**: Development and testing
- **Resources**: Minimal (optimized for laptop)
- **Replicas**: 1 pod per service
- **Storage**: HostPath or local PV
- **Ingress**: NodePort services

### Dev (Kubernetes Cluster)

```bash
helmfile -e dev apply
```

- **Purpose**: Integration testing and staging
- **Resources**: Moderate (cost-optimized)
- **Replicas**: 2-5 pods (HPA enabled)
- **Storage**: Cloud persistent disks (GP3)
- **Ingress**: cert-manager + Let's Encrypt staging
- **Domains**: `*-dev.vision.example.com`

### Prod (Kubernetes Cluster)

```bash
helmfile -e prod apply
```

- **Purpose**: Production workloads
- **Resources**: High (performance-optimized)
- **Replicas**: 3-20 pods (HPA enabled)
- **Storage**: Cloud persistent disks (GP3, replicated)
- **Ingress**: cert-manager + Let's Encrypt prod
- **Domains**: `*.vision.example.com`
- **Security**: Network policies, pod disruption budgets, secrets

## 📁 Repository Structure

```
vision/
├── .github/workflows/       # CI/CD pipelines
│   ├── docker-build.yaml   # Backend image build
│   └── frontend-build.yaml # Frontend image build
├── api/                     # FastAPI + YOLO backend
│   ├── main.py
│   ├── config.py
│   ├── services/
│   └── requirements.txt
├── frontend/                # Static web UI
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── index.html
│   └── app.js
├── docker/                  # Backend Dockerfile
├── charts/                  # Helm charts
│   ├── api/                # Application chart
│   ├── infrastructure/     # Redis, MinIO, Postgres
│   └── monitoring/         # Prometheus stack
├── environments/            # Environment configs
│   ├── local.yaml
│   ├── dev.yaml
│   └── prod.yaml
├── docker-compose.yaml      # Local testing
├── helmfile.yaml           # K8s deployment orchestration
└── README.md
```

## 🛠️ Development Workflow

### 1. Code Changes

```bash
# Make changes to api/ or frontend/
git add .
git commit -m "feat: your feature"
git push origin master
```

### 2. CI/CD Pipeline

- **Triggers**: Push to master/main/develop
- **Backend**: Builds 4.5GB Docker image with PyTorch + YOLO
- **Frontend**: Builds 15MB Nginx image with static files
- **Registry**: Docker Hub (`astitvaveergarg/vision-api:latest`)

### 3. Deploy Updated Image

```bash
# Local: Minikube loads image directly
minikube image load astitvaveergarg/vision-api:latest
helmfile -e local apply

# Cloud: Pulls from Docker Hub
helmfile -e dev apply
helmfile -e prod apply
```

## 📊 Monitoring

### Prometheus Metrics

- `http_requests_total` - Total API requests
- `inference_duration_seconds` - YOLO inference latency
- `cache_hits_total` / `cache_misses_total` - Cache efficiency

### Grafana Dashboards

1. **API Performance**: Request rate, latency (p50/p95/p99), errors
2. **ML Metrics**: Inference time, model usage, cache hit ratio
3. **Infrastructure**: CPU, memory, network, storage per pod
4. **Kubernetes**: Pod health, HPA scaling events

### Access Grafana

```bash
# Local
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Cloud (with ingress)
# Dev: https://grafana-dev.vision.example.com
# Prod: https://grafana.vision.example.com
```

## 🔒 Security

### Secrets Management

```bash
# Create secrets for dev/prod
kubectl create secret generic minio-credentials \
  --from-literal=access-key=YOUR_ACCESS_KEY \
  --from-literal=secret-key=YOUR_SECRET_KEY \
  -n vision-infra

kubectl create secret generic redis-credentials \
  --from-literal=password=YOUR_REDIS_PASSWORD \
  -n vision-infra
```

### Network Policies

- Deny all ingress by default
- Allow only required service-to-service communication
- Apply in dev and prod (not local)

## 🚢 Deployment Commands

### Deploy Everything

```bash
# Local
helmfile -e local apply

# Dev
helmfile -e dev apply

# Prod
helmfile -e prod apply
```

### Deploy Specific Services

```bash
# Infrastructure only
helmfile -e local -l name=redis apply
helmfile -e local -l name=minio apply

# Monitoring only
helmfile -e local -l name=prometheus apply

# Application only
helmfile -e local -l name=vision-api apply
```

### Update Application

```bash
# Update image tag
helm upgrade vision-api ./charts/api -n vision-app \
  --set image.tag=v1.1.0 \
  --reuse-values

# Or update via helmfile
helmfile -e prod -l name=vision-api apply
```

### Rollback

```bash
# Helm rollback
helm rollback vision-api -n vision-app

# Or kubectl rollback
kubectl rollout undo deployment/vision-api -n vision-app
```

## 📈 Scaling

### Manual Scaling

```bash
kubectl scale deployment vision-api --replicas=5 -n vision-app
```

### Auto-Scaling (HPA)

```yaml
# Already configured in values-dev.yaml and values-prod.yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## 🧪 Testing

### API Testing

```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/models

# Detection
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" \
  -F "model=yolov8n"
```

### Load Testing

```bash
# Using k6 (install from https://k6.io)
k6 run tests/load/test_api.js
```

## 🔧 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n vision-app

# View logs
kubectl logs -f deployment/vision-api -n vision-app

# Describe pod
kubectl describe pod <pod-name> -n vision-app
```

### Image Pull Errors

```bash
# Check image exists
docker pull astitvaveergarg/vision-api:latest

# Load into Minikube (local only)
minikube image load astitvaveergarg/vision-api:latest
```

### Service Connection Issues

```bash
# Test Redis
kubectl run -it --rm redis-test --image=redis:alpine --restart=Never -- \
  redis-cli -h redis-master.vision-infra.svc.cluster.local ping

# Test MinIO
kubectl run -it --rm minio-test --image=minio/mc --restart=Never -- \
  mc alias set minio http://minio.vision-infra.svc.cluster.local:9000 minioadmin minioadmin
```

## 👥 Contributors

@ Astitva Veer Garg

---

**Last Updated**: February 13, 2026
