# 🎯 VisionOps - Production MLOps Platform

> **A showcase of modern DevOps and MLOps practices** - Deploying YOLO object detection at scale with Kubernetes, Terraform, and complete CI/CD automation.

[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=fff)](#)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=fff)](#)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=fff)](#)
[![GCP](https://img.shields.io/badge/GCP-4285F4?logo=googlecloud&logoColor=fff)](#)
[![AWS](https://img.shields.io/badge/AWS-232F3E?logo=amazonaws&logoColor=fff)](#)
[![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoftazure&logoColor=fff)](#)
[![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=fff)](#)

---

## 📖 Overview

**VisionOps** is a production-grade ML inference platform demonstrating enterprise-level DevOps and MLOps practices. It serves real-time object detection using YOLOv8 models with auto-scaling, caching, monitoring, and multi-cloud deployment capabilities.

**Why this project stands out:**
- 🚀 **Cloud-Native Architecture**: Kubernetes-native design with split frontend/backend Helm charts and Helmfile orchestration
- 🔒 **Security-First**: Private clusters, CDN-only access, WAF protection, non-root containers
- 📊 **Observable**: Complete monitoring stack with Prometheus, Grafana, and custom metrics
- ⚡ **Performance**: Redis caching, model LRU management, horizontal pod autoscaling
- 🌍 **Multi-Cloud IaC**: Terraform configurations for GCP GKE, AWS EKS, and Azure AKS
- 🔄 **Full CI/CD**: Automated image builds and deployments via GitHub Actions

---

## 🏗️ Architecture

```
Internet
   │
   ▼
ingress-nginx (External LoadBalancer IP)
   │
   ▼
vision-frontend pod  (nginx:alpine 15MB)
├── GET /           → serves index.html (static)
└── ANY /api/*      → proxy_pass → vision-api:8000/   (ClusterIP only)
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
               Redis Cache         MinIO Storage
            (vision-infra)        (vision-infra)
```

**Key Design Decisions:**
- **Split Charts**: `charts/frontend/` (nginx) and `charts/api/` (FastAPI) deployed as separate Helm releases
- **nginx Proxy**: Frontend proxies `/api/*` → `vision-api.vision-app.svc.cluster.local:8000/`
- **root_path=/api**: FastAPI ROOT_PATH env var set so Swagger UI resolves openapi.json correctly through nginx
- **ClusterIP Backend**: `vision-api` has no Ingress — reachable only from within cluster via the frontend proxy
- **Runtime Models**: YOLO weights downloaded at startup onto a PVC (not baked into Docker image)

---

## 🛠️ Technology Stack

| Category | Technologies | Purpose |
|----------|-------------|---------|
| **Application** | FastAPI, YOLOv8 (Ultralytics), PyTorch, Python 3.11 | REST API for object detection |
| **Frontend** | Nginx Alpine, HTML5, Tailwind CSS, Vanilla JS | UI + reverse proxy to backend |
| **Containerization** | Docker multi-stage builds | Optimised images (4.5GB backend, 15MB frontend) |
| **Orchestration** | Kubernetes, Helm 3, Helmfile | Declarative multi-environment deployments |
| **Infrastructure** | Terraform, GCP GKE (active), AWS EKS (IaC), Azure AKS (IaC) | Multi-cloud provisioning |
| **CI/CD** | GitHub Actions (docker-build.yaml, frontend-build.yaml) | Automated build + push |
| **Data Layer** | Redis (Bitnami chart), MinIO (Bitnami chart) | Caching & S3-compatible storage |
| **Monitoring** | kube-prometheus-stack (Prometheus + Grafana) | Metrics & dashboards |
| **Security** | Cloud Armor (GCP), CloudFront+WAF (AWS), Front Door+WAF (Azure) | DDoS, WAF, CDN |

---

## ✨ Key Features

| Feature | Implementation | Benefit |
|---------|---------------|---------|
| **Multi-Model Support** | 5 YOLOv8 variants (nano/small/medium/large/xlarge) selectable per request | Flexible speed/accuracy tradeoff |
| **Smart Caching** | Redis result cache keyed by `sha256(image)+model_id`, TTL 3600s | 10x faster repeated detections |
| **Split Frontend/Backend** | Separate Helm charts, nginx reverse proxy | Independent scaling, smaller attack surface |
| **Auto-Scaling** | HPA (CPU 70%, Mem 80%) — on in prod, off in dev | Cost-efficient resource usage |
| **High Availability** | PodDisruptionBudgets + anti-affinity (prod) | Zero-downtime deployments |
| **Full Observability** | Custom Prometheus metrics at `/api/metrics` + Grafana | Real-time performance insights |
| **API Documentation** | Swagger UI at `/api/docs`, ReDoc at `/api/redoc` | Developer-friendly |

---

## 📊 Environment Configurations

| Environment | Local (Minikube) | Dev (GKE) | Prod (Cloud) |
|-------------|-----------------|-----------|--------------|
| **Cluster** | Minikube | GKE `vision-dev-gke` us-central1-a | GKE / EKS / AKS |
| **Replicas** | 1 | 1 (HPA off — RWO PVC constraint) | 3-20 (HPA on) |
| **Storage** | HostPath | `standard` (pd-standard HDD) | `premium-rwo` (pd-ssd) |
| **Access** | Port-forward | External IP (ingress-nginx) | CDN + Custom Domain |
| **Infra cost** | Free | ~$0.16/hr (1× e2-standard-4) | ~$0.65/hr (2-4 nodes) |

---

## 📂 Project Structure

```
vision/
├── api/                          # FastAPI ML application
│   ├── main.py                   # Routes, lifespan, Prometheus metrics, root_path
│   ├── config.py                 # Settings via pydantic-settings (ROOT_PATH, etc.)
│   ├── requirements-cpu.txt      # CPU-only dependencies (used in Docker image)
│   └── services/
│       ├── detector.py          # YOLOv8 inference + ModelManager (LRU)
│       ├── cache.py             # Redis caching layer
│       └── storage.py           # MinIO S3 client
│
├── frontend/                     # Static files baked into vision-frontend image
│   └── index.html               # Web UI — footer links use /api/* paths
│
├── docker/
│   ├── Dockerfile               # Multi-stage backend (GPU)
│   └── Dockerfile.cpu           # Multi-stage backend (CPU — used in Kubernetes)
│
├── charts/
│   ├── api/                    # vision-api Helm chart (backend)
│   │   ├── values.yaml         # Base: ROOT_PATH=/api, secret names, ClusterIP
│   │   ├── values-local.yaml   # Minikube: secretKeyRef, PDB/NP disabled
│   │   ├── values-dev.yaml     # GKE dev: autoscaling off, storageClass standard
│   │   └── values-prod.yaml    # Prod: autoscaling on, premium-rwo, PDB on
│   ├── frontend/               # vision-frontend Helm chart (nginx)
│   │   ├── templates/configmap.yaml  # nginx.conf with /api/ proxy_pass
│   │   ├── templates/ingress.yaml    # Ingress (enabled in dev/prod)
│   │   ├── values.yaml         # Base: backend.service = vision-api FQDN
│   │   ├── values-local.yaml   # ingress.enabled: false
│   │   ├── values-dev.yaml     # ingress.enabled: true, pullPolicy: Always
│   │   └── values-prod.yaml    # replicaCount: 2, CDN annotations
│   └── infrastructure/
│       ├── redis/              # Bitnami Redis, existingSecret
│       ├── minio/              # Bitnami MinIO, existingSecret
│       └── monitoring/         # kube-prometheus-stack
│
├── helmfile.yaml.gotmpl          # 6 releases: ingress-nginx, redis, minio,
│                                 #   prometheus, vision-api, vision-frontend
├── environments/
│   ├── local.yaml              # frontend.enabled: true, ingress.enabled: false
│   ├── dev.yaml                # frontend.enabled: true, ingress.enabled: true
│   └── prod.yaml               # frontend.enabled: true, ingress.enabled: true
│
├── k8s/
│   ├── secrets-dev.yaml.example    # Template: vision-redis/minio/grafana-credentials
│   ├── secrets-local.yaml.example  # Template for Minikube
│   └── secrets-prod.yaml.example   # Template for production
│
├── terraform/
│   ├── gcp/                    # ✅ ACTIVE — GKE cluster (vision-dev-gke)
│   │   ├── gke.tf              # Cluster, node pools (general + ml)
│   │   ├── billing.tf          # Budget alerts
│   │   ├── cloud_armor.tf      # WAF (prod only)
│   │   ├── budget_enforcer.tf  # Cloud Function: auto-destroy on overspend
│   │   └── environments/       # dev.tfvars, prod.tfvars
│   ├── aws/                    # ⏳ IaC complete, cluster not yet provisioned
│   └── azure/                  # ⏳ IaC complete, cluster not yet provisioned
│
├── .github/workflows/
│   ├── docker-build.yaml       # Backend: builds astitvaveergarg/vision-api
│   └── frontend-build.yaml     # Frontend: builds astitvaveergarg/vision-frontend
│
└── docker-compose.yaml          # Local full-stack testing
```

---

## 🚀 Quick Start

### 🌐 Live Demo (GKE - vision-ops.xyz)

**Application URLs:**
- 🎨 **Frontend UI**: https://vision-ops.xyz/
- 📡 **API Docs**: https://vision-ops.xyz/api/docs
- 💚 **Health Check**: https://vision-ops.xyz/api/health
- 📊 **Metrics**: https://vision-ops.xyz/api/metrics
- 📈 **Grafana**: https://vision-ops.xyz/grafana/
- 🚀 **ArgoCD**: https://argocd.vision-ops.xyz/

**Demo Access:**

**Grafana (Monitoring):**
- **Username**: `vision-ops-viewers`
- **Password**: `vision-ops-2026`
- *(Read-only viewer access)*

**ArgoCD (GitOps):**
- **Username**: `admin`
- **Password**: *(See "Accessing ArgoCD" section below for retrieve command)*
- *(Admin access for GitOps management)*

**ArgoCD (Read-Only Viewer):**
- **Username**: `viewer`
- **Password**: `vision-readonly-2026`
- *(Read-only access for monitoring deployments)*

---

### GKE (Active — Recommended)

```bash
# 1. Authenticate and connect
gcloud auth login
gcloud container clusters get-credentials vision-dev-gke \
  --location us-central1-a --project YOUR_PROJECT_ID

# 2. Create namespaces and secrets
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl create namespace ingress-nginx

# Copy and fill in credentials, then apply
cp k8s/secrets-dev.yaml.example k8s/secrets-dev.yaml
# Edit k8s/secrets-dev.yaml with real values
kubectl apply -f k8s/secrets-dev.yaml

# 3. Deploy all 6 releases
helmfile -e dev sync

# 4. Find external IP (wait ~2 min for provisioning)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 5. Access the application
# Frontend UI:  http://<EXTERNAL-IP>/
# API Docs:     http://<EXTERNAL-IP>/api/docs
# Health check: http://<EXTERNAL-IP>/api/health
# Metrics:      http://<EXTERNAL-IP>/api/metrics
# Grafana:      kubectl port-forward svc/prometheus-grafana 3000:80 -n vision-monitoring
```

### Docker Compose (Local)

```bash
# Start infrastructure
minikube start --cpus=4 --memory=8192
helmfile -e local apply
kubectl port-forward -n vision-infra svc/redis-master 6379:6379 &
kubectl port-forward -n vision-infra svc/minio 9000:9000 &

# Launch stack
docker-compose up -d
# http://localhost      → Frontend
# http://localhost:8000/docs → API (direct, no nginx proxy)
```

---

## � GitOps with ArgoCD

### Accessing ArgoCD

**Live:** https://argocd.vision-ops.xyz/

**Local Port Forward:**
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
# http://localhost:8080
```

**Default Credentials:**

**Admin (Full Access):**
- **Username**: `admin`
- **Password**: `ArgoAdmin2026!`

**Viewer (Read-Only Access):**
- **Username**: `viewer`
- **Password**: `vision-readonly-2026`

> 💡 **Security Best Practice**: Change the admin password via UI after first login (User Info → Update Password).

### What ArgoCD Does

ArgoCD enables **GitOps** - declarative continuous delivery for Kubernetes:
- Automatically syncs cluster state with Git repository
- Provides visual UI for deployment status
- Automated rollbacks and health checks
- Multi-cluster management capabilities

### Managed Applications

VisionOps is now managed by ArgoCD with 5 applications:

```bash
# View all applications
kubectl get applications -n argocd

# Create applications from Git
kubectl apply -f k8s/argocd-apps/
```

**Applications:**
1. **vision-api** - FastAPI backend (charts/api)
2. **vision-frontend** - Nginx frontend (charts/frontend)
3. **vision-infra-redis** - Redis cache (charts/infrastructure/redis)
4. **vision-infra-minio** - MinIO storage (charts/infrastructure/minio)
5. **vision-monitoring** - Prometheus + Grafana (charts/monitoring/prometheus)

**Features:**
- ✅ Auto-sync enabled (Git → Cluster)
- ✅ Self-heal enabled (auto-recover from drift)
- ✅ Prune enabled (removes deleted resources)
- 🎯 Source: GitHub repository `astitvaveergarg/Vision-Ops`
- 📂 All apps use `values-dev.yaml` for environment config

---

## �📊 Monitoring

### Accessing Grafana

**Live:** https://vision-ops.xyz/grafana/

**Local Port Forward:**
```bash
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80
# http://localhost:3000
```

**Demo Credentials (Viewer Access):**
- **Username**: `vision-ops-viewers`
- **Password**: `vision-ops-2026`

> ⚠️ **Admin credentials**: Stored securely in `k8s/secrets-dev.yaml` (gitignored)

### Custom Metrics

Available at `/api/metrics`:
```
http_requests_total              — request rate by method/endpoint/status
inference_duration_seconds       — YOLO inference latency histogram
cache_hits_total                 — Redis cache hits
cache_misses_total               — Redis cache misses
```

---

## 🔧 Quick Troubleshooting

| Symptom | First command | Common fix |
|---------|--------------|------------|
| Swagger UI parser error | `kubectl exec deploy/vision-api -n vision-app -- env \| grep ROOT_PATH` | Should be `/api` — already set in values.yaml |
| Pods Pending | `kubectl describe pod -n vision-app` | Check resources, storage class, or PVC |
| CrashLoopBackOff | `kubectl logs -n vision-app --previous` | Missing secret, can't reach Redis/MinIO |
| ImagePullBackOff | Check [GitHub Actions](https://github.com/astitvaveergarg/Vision-Ops/actions) | CI not finished yet |
| 502 from nginx | `kubectl logs deploy/vision-frontend -n vision-app` | vision-api pod not ready |

Full guide: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, component deep-dive, data flow |
| [docs/API.md](docs/API.md) | API reference — endpoints, parameters, response schemas |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step deployment guide for all environments |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Diagnostics, common issues, emergency procedures |
| [PRIVATE_CLUSTER_GUIDE.md](PRIVATE_CLUSTER_GUIDE.md) | VPN setup, CDN access for private AWS/Azure clusters |
| [PRE_TESTING_CHECKLIST.md](PRE_TESTING_CHECKLIST.md) | Checklist before deploying to any cluster |
| [terraform/gcp/README.md](terraform/gcp/README.md) | GCP GKE Terraform — active deployment |
| [terraform/aws/README.md](terraform/aws/README.md) | AWS EKS Terraform (IaC complete, not provisioned) |
| [terraform/azure/README.md](terraform/azure/README.md) | Azure AKS Terraform (IaC complete, not provisioned) |

---

**Author**: Astitva Veer Garg  |  **GitHub**: [@astitvaveergarg](https://github.com/astitvaveergarg)  |  **Repo**: [Vision-Ops](https://github.com/astitvaveergarg/Vision-Ops)

*Last Updated: March 2026 — GKE active, frontend/backend split complete, Swagger root_path fix applied*
