# GitHub Copilot Instructions for VisionOps

> **Context**: You are developing VisionOps, a production-grade ML inference platform  
> **Role**: Senior DevOps/MLOps Engineer  
> **Goal**: Build, deploy, and maintain a scalable YOLO detection service on Kubernetes

---

## 🎯 Project Context

**What you're building:**
A cloud-native object detection API using YOLO, deployed on Kubernetes with complete observability, caching, and GitOps practices.

**Why it matters:**
This demonstrates real-world ML deployment practices used by production engineering teams, not just ML model training.

**Tech stack:**
- **App**: FastAPI + YOLOv8 + Python
- **Orchestration**: Kubernetes + Helm + Helmfile
- **Services**: Redis, MinIO, PostgreSQL
- **Monitoring**: Prometheus + Grafana
- **CI/CD**: GitHub Actions
- **Cloud**: AWS EKS (later)

---

## 📁 Repository Structure

```
vision/
├── api/                          # FastAPI application
│   ├── main.py                   # API entrypoint
│   ├── config.py                 # Configuration (env-aware)
│   ├── requirements.txt          # Python dependencies
│   ├── services/                 # Business logic
│   │   ├── cache.py             # Redis caching
│   │   ├── storage.py           # MinIO/S3 storage
│   │   └── detector.py          # YOLO inference
│   └── tests/                    # Unit & integration tests
│
├── docker/
│   └── Dockerfile                # Multi-stage production image
│
├── charts/                       # Helm charts
│   ├── infrastructure/
│   │   ├── redis/               # Redis cache
│   │   ├── minio/               # Object storage
│   │   ├── postgres/            # Database (optional)
│   │   └── monitoring/          # Prometheus + Grafana
│   └── api/                      # Application chart
│       ├── Chart.yaml
│       ├── values.yaml          # Base values
│       ├── values-local.yaml    # Local overrides
│       ├── values-prod.yaml     # Production overrides
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── hpa.yaml
│           └── ingress.yaml
│
├── helmfile.yaml                 # Orchestrates all releases
│
├── environments/                 # Environment-specific configs
│   ├── local.yaml               # Minikube (default)
│   ├── dev.yaml                 # Development cluster
│   └── prod.yaml                # Production (EKS)
│
├── scripts/                      # Helper scripts
│   ├── start-minikube.ps1       # Initialize Minikube
│   ├── deploy-infrastructure.ps1
│   ├── check-services.ps1
│   └── test-connections.ps1
│
├── terraform/                    # IaC for cloud resources
│   ├── main.tf
│   ├── eks.tf
│   └── environments/
│
├── .github/workflows/            # CI/CD pipelines
│   ├── ci.yaml
│   └── cd.yaml
│
├── docs/
│   ├── DEPLOYMENT_PLAN.md       # Complete deployment guide
│   ├── architecture.md
│   └── API.md
│
└── models/                       # YOLO model files
    └── .gitkeep
```

---

## 🧠 Development Philosophy

### Three-Phase Approach

**Phase 1: Infrastructure (Current)**
- Deploy Redis, MinIO, Monitoring to Minikube
- Expose via NodePort for local development
- Zero application code yet

**Phase 2: Local Development**
- Build FastAPI app on host machine
- Connect to Minikube services
- Fast iteration (no Docker rebuilds)
- Full functionality without containerization

**Phase 3: Kubernetes Deployment**
- Containerize application
- Create Helm chart
- Deploy complete stack to K8s
- Enable auto-scaling, monitoring

### Key Principles

1. **Local-first**: If it doesn't work in Minikube, don't touch cloud
2. **Environment parity**: Same Helm charts everywhere, only values differ
3. **Incremental**: Build → Test → Deploy one component at a time
4. **Observable**: Metrics, logs, traces from day one
5. **Reproducible**: One command to deploy everything

---

## 💻 Daily Development Workflow

### Morning Routine
```powershell
# 1. Start infrastructure
cd d:\Development\Vision\vision
.\scripts\start-minikube.ps1
.\scripts\deploy-infrastructure.ps1

# 2. Verify services
.\scripts\check-services.ps1
.\scripts\test-connections.ps1

# 3. Start local development
cd api
.\venv\Scripts\Activate.ps1
python main.py
```

### Coding Loop
```
1. Edit code in api/
2. Save (API auto-reloads with --reload)
3. Test with curl/Postman
4. Check logs in terminal
5. Verify in Grafana/MinIO console
6. Iterate
```

### Deploy to Kubernetes
```powershell
# 1. Build image
docker build -t vision-api:dev -f docker/Dockerfile .

# 2. Load into Minikube
minikube image load vision-api:dev

# 3. Deploy/Update
helmfile -e local sync

# 4. Verify
kubectl get pods -n vision-app
kubectl logs -f deployment/vision-api -n vision-app
```

---

## 🎨 Coding Guidelines

### Python Code Style
- **PEP 8 compliant**
- **Type hints** everywhere
- **Docstrings** for public functions
- **Async/await** for I/O operations
- **Error handling** with proper exceptions

### FastAPI Patterns
```python
# Good: Dependency injection
from fastapi import Depends

def get_cache_service():
    return CacheService()

@app.post("/detect")
async def detect(
    file: UploadFile,
    cache: CacheService = Depends(get_cache_service)
):
    ...
```

### Configuration Management
```python
# Good: Environment-aware config
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    REDIS_HOST: str = "localhost"  # Local default
    REDIS_PORT: int = 30379
    
    class Config:
        env_file = ".env"  # Override with .env file
```

### Service Layer Pattern
```python
# Separate business logic from routes
# api/services/detector.py
class DetectorService:
    def detect(self, image: bytes) -> List[Detection]:
        ...

# api/main.py
detector = DetectorService()

@app.post("/detect")
async def detect_endpoint(file: UploadFile):
    return detector.detect(await file.read())
```

---

## ☸️ Kubernetes Patterns

### Resource Limits
```yaml
# Always set requests and limits
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

### Health Checks
```yaml
# Liveness: Is the app running?
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 10

# Readiness: Can it serve traffic?
readinessProbe:
  httpGet:
    path: /ready
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 5
```

### ConfigMaps & Secrets
```yaml
# ConfigMap for non-sensitive config
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
data:
  MODEL_PATH: "models/yolov8n.pt"
  CACHE_TTL: "3600"

# Secret for sensitive data
apiVersion: v1
kind: Secret
metadata:
  name: api-secrets
type: Opaque
data:
  redis-password: <base64>
  minio-secret-key: <base64>
```

### Horizontal Pod Autoscaling
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vision-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vision-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## 🔍 Debugging Guide

### Check Pod Status
```powershell
# List pods
kubectl get pods -n vision-app

# Describe pod (events, config)
kubectl describe pod <pod-name> -n vision-app

# View logs
kubectl logs -f <pod-name> -n vision-app

# Previous logs (if crashed)
kubectl logs <pod-name> -n vision-app --previous

# Multiple containers in pod
kubectl logs <pod-name> -c <container-name> -n vision-app
```

### Shell Into Container
```powershell
# Interactive shell
kubectl exec -it <pod-name> -n vision-app -- /bin/bash

# Run command
kubectl exec <pod-name> -n vision-app -- python -c "import redis; print('OK')"

# Check environment variables
kubectl exec <pod-name> -n vision-app -- env
```

### Network Debugging
```powershell
# Test service connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash
# Inside: nslookup redis-master.vision-infra.svc.cluster.local

# Port forward service
kubectl port-forward svc/vision-api 8000:8000 -n vision-app

# Check service endpoints
kubectl get endpoints -n vision-app
```

### Common Issues

**ImagePullBackOff**
```powershell
# Image not in Minikube
minikube image ls | grep vision-api

# Solution
minikube image load vision-api:dev
```

**CrashLoopBackOff**
```powershell
# Check logs
kubectl logs <pod-name> -n vision-app

# Common causes:
# - Missing environment variables
# - Can't connect to Redis/MinIO
# - Model file not found
# - Port already in use
```

**Pods Pending**
```powershell
# Check events
kubectl get events -n vision-app --sort-by='.lastTimestamp'

# Common causes:
# - Insufficient resources
# - PVC not bound
# - Node selector mismatch
```

---

## 📊 Monitoring & Metrics

### Application Metrics (Prometheus)
```python
# api/metrics.py
from prometheus_client import Counter, Histogram, Gauge

# Request metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

# Latency metrics
INFERENCE_DURATION = Histogram(
    'inference_duration_seconds',
    'YOLO inference duration'
)

# Cache metrics
CACHE_HITS = Counter('cache_hits_total', 'Cache hits')
CACHE_MISSES = Counter('cache_misses_total', 'Cache misses')

# Usage in code
@INFERENCE_DURATION.time()
def detect_objects(image: bytes):
    result = model(image)
    return result
```

### Grafana Dashboards

**Key Metrics to Display:**
1. Request rate (req/sec)
2. Latency percentiles (p50, p95, p99)
3. Error rate (%)
4. Cache hit ratio (%)
5. CPU/Memory per pod
6. Pod count (autoscaling)

**PromQL Queries:**
```promql
# Request rate
rate(http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m]))

# Cache efficiency
(cache_hits_total / (cache_hits_total + cache_misses_total)) * 100

# Pod count
count(kube_pod_info{namespace="vision-app"})
```

---

## 🧪 Testing Strategy

### Unit Tests
```python
# tests/unit/test_detector.py
import pytest
from services.detector import DetectorService

def test_detector_initialization():
    detector = DetectorService()
    assert detector.model is not None

def test_detect_objects():
    detector = DetectorService()
    with open("test_image.jpg", "rb") as f:
        result = detector.detect(f.read())
    
    assert len(result) > 0
    assert "class" in result[0]
    assert "confidence" in result[0]
```

### Integration Tests
```python
# tests/integration/test_api.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["redis"] == "healthy"

def test_detect_endpoint():
    with open("test_image.jpg", "rb") as f:
        response = client.post(
            "/detect",
            files={"file": ("image.jpg", f, "image/jpeg")}
        )
    
    assert response.status_code == 200
    data = response.json()
    assert "detections" in data
```

### Load Tests (k6)
```javascript
// tests/load/test_api.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
};

export default function() {
  const file = open('test_image.jpg', 'b');
  const res = http.post('http://localhost:8000/detect', {
    file: http.file(file, 'image.jpg'),
  });
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 2s': (r) => r.timings.duration < 2000,
  });
}
```

---

## 🚀 Deployment Checklist

### Before Deploying

- [ ] All tests pass locally
- [ ] Code reviewed
- [ ] No secrets in code
- [ ] Environment variables documented
- [ ] Resource limits defined
- [ ] Health checks implemented
- [ ] Metrics instrumented
- [ ] Logs structured (JSON)

### Deployment Steps

1. **Build & Tag**
   ```powershell
   docker build -t vision-api:v1.0.0 -f docker/Dockerfile .
   ```

2. **Test Image Locally**
   ```powershell
   docker run -p 8000:8000 vision-api:v1.0.0
   ```

3. **Load to Minikube**
   ```powershell
   minikube image load vision-api:v1.0.0
   ```

4. **Update Values**
   ```yaml
   # charts/api/values-local.yaml
   image:
     tag: v1.0.0
   ```

5. **Deploy**
   ```powershell
   helmfile -e local apply
   ```

6. **Verify**
   ```powershell
   kubectl rollout status deployment/vision-api -n vision-app
   kubectl get pods -n vision-app
   ```

7. **Test**
   ```powershell
   kubectl port-forward svc/vision-api 8000:8000 -n vision-app
   curl -X POST http://localhost:8000/detect -F "file=@test.jpg"
   ```

### Post-Deployment

- [ ] Check metrics in Grafana
- [ ] Verify logs in Prometheus
- [ ] Test all endpoints
- [ ] Monitor error rates
- [ ] Check HPA scaling
- [ ] Update documentation

---

## 🎓 Learning Resources

### Kubernetes
- [Kubernetes Docs](https://kubernetes.io/docs/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helmfile Guide](https://helmfile.readthedocs.io/)

### FastAPI
- [FastAPI Docs](https://fastapi.tiangolo.com/)
- [Async Programming](https://fastapi.tiangolo.com/async/)

### YOLO
- [Ultralytics Docs](https://docs.ultralytics.com/)
- [YOLOv8 Guide](https://docs.ultralytics.com/models/yolov8/)

### Monitoring
- [Prometheus Query Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Tutorials](https://grafana.com/tutorials/)

---

## 💡 Tips for GitHub Copilot

When asking me for help, be specific:

**Good prompts:**
- "Create a Redis cache service with TTL support"
- "Add Prometheus metrics for inference latency"
- "Write Helm values for HPA with CPU target 70%"
- "Create integration test for /detect endpoint"

**Bad prompts:**
- "Fix the code"
- "Make it work"
- "Add monitoring"

**Context I need:**
- What phase are you in? (Infra, Local Dev, K8s)
- What services are running?
- What error are you seeing?
- What have you tried?

**I can help with:**
- ✅ Writing Python/FastAPI code
- ✅ Creating Helm charts
- ✅ Writing Kubernetes manifests
- ✅ Debugging deployment issues
- ✅ Writing tests
- ✅ Creating monitoring dashboards
- ✅ Optimizing performance

**I can't:**
- ❌ Access your Minikube cluster
- ❌ Run commands on your machine
- ❌ Deploy to production without approval

---

## 🎯 Current Status

**Phase 1: Infrastructure Setup** ✅
- Minikube running
- Helmfile configured
- Redis deployed (NodePort 30379)
- MinIO deployed (NodePort 30900)
- Monitoring deployed (Grafana on 30300)

**Phase 2: Local Development** 🚧
- FastAPI skeleton created
- Config points to Minikube services
- Next: Implement cache, storage, detector services

**Phase 3: Kubernetes Deployment** ⏳
- Dockerfile ready
- Helm chart structure ready
- Waiting for Phase 2 completion

---

## 📞 Quick Reference

### Service URLs (Local)
- **API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Redis**: localhost:30379
- **MinIO**: http://localhost:30900
- **MinIO Console**: http://localhost:30901
- **Grafana**: http://localhost:30300 (admin/admin)

### Common Commands
```powershell
# Deploy everything
helmfile -e local apply

# Check status
kubectl get pods -A

# View logs
kubectl logs -f deployment/vision-api -n vision-app

# Shell into pod
kubectl exec -it <pod> -n vision-app -- /bin/bash

# Delete everything
helmfile -e local delete
minikube delete
```

---

**Last Updated:** February 12, 2026  
**Version:** 1.0  
**Maintainer:** Development Team
