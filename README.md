# VisionOps — Cloud-Native AI Inference Platform

> Production-grade YOLO object detection on Kubernetes with GitOps

## Quick Start

```bash
# Phase 1: Infrastructure
minikube start
helmfile -e local apply

# Phase 2: Local Development
cd api
pip install -r requirements.txt
python main.py

# Phase 3: Full K8s Deployment
docker build -t vision-api:dev -f docker/Dockerfile .
helmfile -e local sync
```

## Architecture

```
User → Ingress → FastAPI → Redis Cache → YOLO Model → MinIO Storage
                              ↓
                    Prometheus/Grafana
```

## Documentation

- [Deployment Plan](docs/DEPLOYMENT_PLAN.md)
- [Developer Guide](docs/DEVELOPER_GUIDE.md)
- [Architecture](docs/architecture.md)

## Stack

- **App**: FastAPI + YOLOv8
- **Infra**: Kubernetes + Helm + Helmfile
- **GitOps**: ArgoCD
- **Monitoring**: Prometheus + Grafana
- **Storage**: MinIO (local) / S3 (cloud)
