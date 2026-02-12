# Quick Start Guide

## Prerequisites

Ensure you have:
- [x] Docker installed
- [x] Minikube installed
- [x] kubectl installed
- [x] Helm installed
- [x] Helmfile installed
- [x] Python 3.11+ installed

## Phase 1: Infrastructure Setup (15 minutes)

### Step 1: Start Minikube
```powershell
cd d:\Development\Vision\vision
.\scripts\start-minikube.ps1
```

### Step 2: Deploy Infrastructure
```powershell
.\scripts\deploy-infrastructure.ps1
```

### Step 3: Verify Services
```powershell
.\scripts\check-services.ps1
.\scripts\test-connections.ps1
```

**Expected Output:**
- ✅ Redis: localhost:30379
- ✅ MinIO: localhost:30900
- ✅ Grafana: localhost:30300

---

## Phase 2: Local Development (10 minutes)

### Step 1: Setup Python Environment
```powershell
cd api
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Step 2: Configure Environment
```powershell
cp .env.example .env
```

### Step 3: Download YOLO Model
```powershell
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"
```

### Step 4: Start API
```powershell
python main.py
```

**Access:**
- API: http://localhost:8000
- Docs: http://localhost:8000/docs

### Step 5: Test
```powershell
# Health check
curl http://localhost:8000/health

# Upload test image
curl -X POST http://localhost:8000/detect -F "file=@test_image.jpg"
```

---

## Phase 3: Kubernetes Deployment (5 minutes)

### Step 1: Build Docker Image
```powershell
docker build -t vision-api:dev -f docker\Dockerfile .
minikube image load vision-api:dev
```

### Step 2: Deploy to Kubernetes
```powershell
helmfile -e local sync
```

### Step 3: Verify
```powershell
kubectl get pods -n vision-app
kubectl port-forward svc/vision-api 8000:8000 -n vision-app
```

---

## Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| API | http://localhost:8000 | - |
| API Docs | http://localhost:8000/docs | - |
| Grafana | http://localhost:30300 | admin/admin |
| MinIO Console | http://localhost:30901 | minioadmin/minioadmin |

---

## Troubleshooting

**Problem: Minikube won't start**
```powershell
minikube delete
minikube start --driver=docker
```

**Problem: Services not accessible**
```powershell
kubectl get svc -A
minikube service list
```

**Problem: Pods crashing**
```powershell
kubectl logs -f <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

---

## Next Steps

1. Read [DEPLOYMENT_PLAN.md](docs/DEPLOYMENT_PLAN.md) for full details
2. Check [.github/COPILOT_INSTRUCTIONS.md](.github/COPILOT_INSTRUCTIONS.md) for development guide
3. Explore [architecture.md](docs/architecture.md) for system design

---

**Questions?** Check the documentation or ask GitHub Copilot!
