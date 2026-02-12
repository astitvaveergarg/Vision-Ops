# VisionOps Deployment Plan

> **Author**: Developer (GitHub Copilot)  
> **Date**: February 2026  
> **Project**: Cloud-Native AI Inference Platform

---

## 🎯 Mission Statement

Build and deploy a production-grade YOLO object detection service using Kubernetes, with a clear path from local development to cloud deployment.

---

## 📋 Three-Phase Development Strategy

### **Phase 1: Infrastructure Setup** ⚙️
Deploy all supporting services in Minikube

### **Phase 2: Local Development** 💻
Build FastAPI application connecting to Minikube services

### **Phase 3: Kubernetes Deployment** ☸️
Containerize and deploy full stack to K8s

---

## 🚀 Phase 1: Infrastructure Setup (Week 1)

### Objective
Get Redis, MinIO, PostgreSQL, and Monitoring running in Minikube with NodePort access for local development.

### Prerequisites Checklist
```powershell
# Verify tools installed
docker --version          # Required: 24.x+
minikube version          # Required: 1.32+
kubectl version --client  # Required: 1.28+
helm version              # Required: 3.13+
helmfile version          # Required: 0.160+
```

### Step 1.1: Start Minikube
```powershell
cd d:\Development\Vision\vision
.\scripts\start-minikube.ps1
```

**Expected Output:**
- ✅ Minikube running with 4 CPUs, 8GB RAM
- ✅ metrics-server addon enabled
- ✅ ingress addon enabled
- ✅ kubectl context set to minikube

**Validation:**
```powershell
kubectl cluster-info
kubectl get nodes
```

### Step 1.2: Deploy Infrastructure Services
```powershell
.\scripts\deploy-infrastructure.ps1 -Environment local
```

**What This Does:**
1. Creates namespaces: `vision-infra`, `vision-monitoring`, `vision-app`
2. Deploys Redis (NodePort 30379)
3. Deploys MinIO (NodePort 30900)
4. Deploys Prometheus + Grafana (NodePort 30300)
5. Waits for all pods to be ready

**Validation:**
```powershell
.\scripts\check-services.ps1
.\scripts\test-connections.ps1
```

**Expected Services:**
| Service | Namespace | NodePort | Access URL |
|---------|-----------|----------|------------|
| Redis | vision-infra | 30379 | localhost:30379 |
| MinIO API | vision-infra | 30900 | http://localhost:30900 |
| MinIO Console | vision-infra | 30901 | http://localhost:30901 |
| Grafana | vision-monitoring | 30300 | http://localhost:30300 |

**Success Criteria:**
- [ ] All pods in `Running` state
- [ ] Redis accepts connections on port 30379
- [ ] MinIO health check returns 200
- [ ] Grafana login page loads
- [ ] Prometheus metrics accessible

### Step 1.3: Verify Infrastructure
```powershell
# Test Redis connection
redis-cli -h localhost -p 30379 ping
# Expected: PONG

# Test MinIO
curl http://localhost:30900/minio/health/live
# Expected: HTTP 200

# Login to Grafana
# URL: http://localhost:30300
# User: admin / Pass: admin
```

### Troubleshooting Phase 1

**Problem: Pods stuck in Pending**
```powershell
kubectl describe pod <pod-name> -n vision-infra
# Check: Insufficient CPU/memory
# Solution: Increase minikube resources
```

**Problem: NodePort not accessible**
```powershell
# Get actual NodePort
kubectl get svc -n vision-infra

# Manual port-forward as fallback
kubectl port-forward svc/redis-master 30379:6379 -n vision-infra
```

**Problem: Image pull errors**
```powershell
# Check internet connection
# Or pre-pull images
minikube ssh docker pull bitnami/redis:latest
```

---

## 💻 Phase 2: Local Application Development (Week 2-3)

### Objective
Build FastAPI + YOLO application that connects to Minikube services, without containerization. Fast iteration cycle.

### Step 2.1: Setup Python Environment
```powershell
cd d:\Development\Vision\vision\api

# Create virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Copy environment config
cp .env.example .env
```

### Step 2.2: Download YOLO Model
```powershell
# Create models directory
mkdir ..\models -Force

# Download YOLOv8 nano model (lightweight)
python -c "from ultralytics import YOLO; model = YOLO('yolov8n.pt'); model.export()"
```

**Model will be saved to:** `~/.cache/torch/hub/ultralytics/`

### Step 2.3: Implement Core Services

#### File: `api/services/cache.py`
```python
"""Redis caching layer"""
import redis
import hashlib
import json
from config import settings

class CacheService:
    def __init__(self):
        self.client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            db=settings.REDIS_DB,
            decode_responses=True
        )
    
    def get_cached_result(self, image_hash: str):
        return self.client.get(f"detection:{image_hash}")
    
    def cache_result(self, image_hash: str, result: dict, ttl: int = 3600):
        self.client.setex(
            f"detection:{image_hash}",
            ttl,
            json.dumps(result)
        )
```

#### File: `api/services/storage.py`
```python
"""MinIO storage layer"""
from minio import Minio
from config import settings

class StorageService:
    def __init__(self):
        self.client = Minio(
            settings.MINIO_ENDPOINT,
            access_key=settings.MINIO_ACCESS_KEY,
            secret_key=settings.MINIO_SECRET_KEY,
            secure=settings.MINIO_SECURE
        )
        self._ensure_bucket()
    
    def _ensure_bucket(self):
        if not self.client.bucket_exists(settings.MINIO_BUCKET):
            self.client.make_bucket(settings.MINIO_BUCKET)
    
    def upload_image(self, filename: str, data: bytes):
        self.client.put_object(
            settings.MINIO_BUCKET,
            filename,
            io.BytesIO(data),
            len(data)
        )
```

#### File: `api/services/detector.py`
```python
"""YOLO detection service"""
from ultralytics import YOLO
from config import settings

class DetectorService:
    def __init__(self):
        self.model = YOLO(settings.MODEL_PATH)
    
    def detect(self, image_bytes: bytes):
        # Run inference
        results = self.model(image_bytes)
        
        # Extract detections
        detections = []
        for r in results:
            for box in r.boxes:
                detections.append({
                    "class": r.names[int(box.cls)],
                    "confidence": float(box.conf),
                    "bbox": box.xyxy[0].tolist()
                })
        
        return detections
```

### Step 2.4: Update Main API
Integrate services into main.py with proper error handling, logging, and metrics.

### Step 2.5: Test Locally
```powershell
# Start API
python main.py

# In another terminal, test
curl http://localhost:8000/health

# Upload test image
curl -X POST http://localhost:8000/detect `
  -F "file=@test_image.jpg"
```

**Success Criteria:**
- [ ] API starts without errors
- [ ] Health endpoint returns Redis/MinIO status
- [ ] Image upload works
- [ ] YOLO inference runs
- [ ] Results cached in Redis
- [ ] Images stored in MinIO
- [ ] Response time < 2 seconds

### Development Workflow
```
1. Edit code in api/
2. API auto-reloads (uvicorn --reload)
3. Test with curl/Postman
4. Check logs
5. Verify in MinIO console (localhost:30901)
6. Check Redis cache
```

**No Docker builds needed yet!**

---

## ☸️ Phase 3: Kubernetes Deployment (Week 4)

### Objective
Containerize application and deploy full stack to Kubernetes using Helm + Helmfile.

### Step 3.1: Build Docker Image
```powershell
cd d:\Development\Vision\vision

# Build image
docker build -t vision-api:dev -f docker/Dockerfile .

# Load into Minikube
minikube image load vision-api:dev
```

**Validation:**
```powershell
minikube ssh
docker images | grep vision-api
```

### Step 3.2: Create Helm Chart

#### File: `charts/api/Chart.yaml`
```yaml
apiVersion: v2
name: vision-api
description: VisionOps AI Inference API
version: 1.0.0
appVersion: "1.0.0"
```

#### File: `charts/api/values.yaml`
```yaml
replicaCount: 2

image:
  repository: vision-api
  tag: dev
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8000

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

redis:
  host: redis-master.vision-infra.svc.cluster.local
  port: 6379

minio:
  endpoint: minio.vision-infra.svc.cluster.local:9000
  accessKey: minioadmin
  secretKey: minioadmin

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

#### File: `charts/api/templates/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "vision-api.fullname" . }}
  namespace: vision-app
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: vision-api
  template:
    metadata:
      labels:
        app: vision-api
    spec:
      containers:
      - name: api
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 8000
        env:
        - name: REDIS_HOST
          value: {{ .Values.redis.host }}
        - name: MINIO_ENDPOINT
          value: {{ .Values.minio.endpoint }}
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
```

### Step 3.3: Update Helmfile
Uncomment API release in helmfile.yaml:
```yaml
- name: vision-api
  namespace: vision-app
  chart: ./charts/api
  values:
    - charts/api/values.yaml
    - charts/api/values-local.yaml
  installed: {{ .Values.api.enabled | default true }}
```

Update `environments/local.yaml`:
```yaml
api:
  enabled: true
```

### Step 3.4: Deploy Complete Stack
```powershell
# Deploy everything (infra + app)
helmfile -e local apply

# Watch deployment
kubectl get pods -n vision-app -w
```

**Validation:**
```powershell
# Check pods
kubectl get pods -n vision-app

# Check HPA
kubectl get hpa -n vision-app

# Test via port-forward
kubectl port-forward svc/vision-api 8000:8000 -n vision-app

# Test endpoint
curl http://localhost:8000/detect -F "file=@test.jpg"
```

### Step 3.5: Setup Ingress (Optional)
```yaml
# File: charts/api/templates/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vision-api
  namespace: vision-app
spec:
  rules:
  - host: vision.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vision-api
            port:
              number: 8000
```

Add to hosts file: `127.0.0.1 vision.local`

**Access:** http://vision.local

---

## 📊 Monitoring & Observability

### Grafana Dashboards

**Login:** http://localhost:30300
- User: admin
- Pass: admin

**Create Dashboard:**
1. Data Source: Prometheus
2. Import dashboard ID: 6417 (Kubernetes Cluster Monitoring)
3. Create custom dashboard for API metrics

**Key Metrics to Track:**
- Request rate (requests/sec)
- Inference latency (p50, p95, p99)
- Cache hit ratio
- Error rate
- CPU/Memory per pod

### Prometheus Queries

```promql
# Request rate
rate(http_requests_total[5m])

# Inference latency p95
histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m]))

# Cache hit ratio
(redis_cache_hits / (redis_cache_hits + redis_cache_misses)) * 100

# Pod CPU usage
container_cpu_usage_seconds_total{namespace="vision-app"}
```

---

## 🧪 Testing Strategy

### Unit Tests
```powershell
cd api
pytest tests/unit/
```

### Integration Tests
```powershell
# Requires Minikube services running
pytest tests/integration/
```

### Load Testing
```powershell
# Using locust or k6
k6 run tests/load/test_api.js
```

**Target Performance:**
- Latency p95 < 500ms (cached)
- Latency p95 < 2s (inference)
- Throughput: 100 req/sec
- Error rate < 0.1%

---

## 🔄 CI/CD Pipeline (GitHub Actions)

### File: `.github/workflows/ci.yaml`
```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          cd api
          pip install -r requirements.txt
      - name: Run tests
        run: pytest api/tests/
      
  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t vision-api:${{ github.sha }} -f docker/Dockerfile .
      - name: Push to registry
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
          docker tag vision-api:${{ github.sha }} ghcr.io/${{ github.repository }}/vision-api:${{ github.sha }}
          docker push ghcr.io/${{ github.repository }}/vision-api:${{ github.sha }}
```

---

## 🌩️ Cloud Deployment (AWS EKS)

### Prerequisites
- AWS account
- Terraform installed
- AWS CLI configured

### Step 1: Provision EKS Cluster
```powershell
cd terraform/

# Initialize
terraform init

# Plan
terraform plan -var-file=environments/prod.tfvars

# Apply
terraform apply -var-file=environments/prod.tfvars
```

### Step 2: Update Environment Values
`environments/prod.yaml`:
```yaml
redis:
  enabled: true
  master:
    persistence:
      enabled: true

minio:
  enabled: false  # Use S3 instead

api:
  enabled: true
  image:
    repository: ghcr.io/yourorg/vision-api
  storage:
    type: s3
    bucket: vision-images-prod
```

### Step 3: Deploy to EKS
```powershell
# Configure kubectl
aws eks update-kubeconfig --name vision-prod

# Deploy
helmfile -e prod apply
```

---

## 🎯 Success Metrics

### Phase 1 Complete When:
- [ ] Minikube running
- [ ] All infra services healthy
- [ ] NodePorts accessible
- [ ] Grafana showing metrics

### Phase 2 Complete When:
- [ ] API runs locally
- [ ] Connects to Minikube services
- [ ] YOLO inference works
- [ ] Caching functional
- [ ] Storage functional

### Phase 3 Complete When:
- [ ] Docker image builds
- [ ] Helm chart deploys
- [ ] Pods running stable
- [ ] HPA scaling works
- [ ] Monitoring integrated

---

## 📚 Reference Commands

### Daily Development
```powershell
# Start everything
.\scripts\start-minikube.ps1
.\scripts\deploy-infrastructure.ps1

# Develop locally
cd api && python main.py

# Deploy to K8s
docker build -t vision-api:dev -f docker/Dockerfile .
minikube image load vision-api:dev
helmfile -e local sync
```

### Debugging
```powershell
# Check logs
kubectl logs -f deployment/vision-api -n vision-app

# Describe pod
kubectl describe pod <pod-name> -n vision-app

# Shell into pod
kubectl exec -it <pod-name> -n vision-app -- /bin/bash

# Check events
kubectl get events -n vision-app --sort-by='.lastTimestamp'
```

### Cleanup
```powershell
# Delete app only
helmfile -e local delete

# Delete everything
minikube delete

# Clean Docker images
docker system prune -a
```

---

## 🚨 Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Pods CrashLoopBackOff | Config error | Check logs: `kubectl logs` |
| ImagePullBackOff | Image not in Minikube | `minikube image load` |
| Service unavailable | NodePort misconfigured | `kubectl get svc` |
| High latency | Resource limits | Increase pod resources |
| Cache misses | Redis connection | Check Redis connectivity |

---

## 📖 Next Steps After Completion

1. **Add Authentication**: JWT tokens, API keys
2. **Add Rate Limiting**: Redis-based rate limiter
3. **Add ArgoCD**: GitOps deployment
4. **Add Logging**: ELK or Loki stack
5. **Add Tracing**: Jaeger or Tempo
6. **Add Frontend**: React UI for image upload
7. **Add Batch Processing**: Celery + RabbitMQ
8. **Add Model Versioning**: MLflow integration

---

**Document Version:** 1.0  
**Last Updated:** February 12, 2026
