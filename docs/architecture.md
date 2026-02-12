# VisionOps Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Request                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   CDN/CloudFront │ (Cloud)
                    │   or Ingress     │ (Local)
                    └────────┬─────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Load Balancer   │
                    │   K8s Ingress    │
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
        ┌──────────────┐          ┌──────────────┐
        │  API Pod 1   │          │  API Pod N   │
        │  FastAPI     │          │  FastAPI     │
        └───────┬──────┘          └───────┬──────┘
                │                         │
                └──────────┬──────────────┘
                           ▼
                  ┌─────────────────┐
                  │  Redis Cache    │
                  │  (vision-infra) │
                  └────────┬─────────┘
                           │
                ┏━━━━━━━━━━┻━━━━━━━━━━┓
                ▼                      ▼
        ┌──────────────┐      ┌──────────────┐
        │ YOLO Model   │      │ Object Store │
        │ YOLOv8       │      │ MinIO / S3   │
        └──────────────┘      └──────────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │  Persistent  │
                              │   Storage    │
                              └──────────────┘

        ┌─────────────────────────────────────┐
        │       Monitoring Layer              │
        │  ┌──────────┐    ┌───────────┐     │
        │  │Prometheus│ ←→ │  Grafana  │     │
        │  └──────────┘    └───────────┘     │
        └─────────────────────────────────────┘
```

## Request Flow

### Happy Path (Cache Hit)
```
1. User uploads image
   ↓
2. Ingress routes to API pod
   ↓
3. API computes image hash
   ↓
4. Check Redis cache
   ↓ (HIT)
5. Return cached result
   
⏱️ Total: ~50-100ms
```

### Full Inference Path (Cache Miss)
```
1. User uploads image
   ↓
2. Ingress routes to API pod
   ↓
3. API computes image hash
   ↓
4. Check Redis cache
   ↓ (MISS)
5. Load YOLO model
   ↓
6. Run inference
   ↓
7. Store image in MinIO/S3
   ↓
8. Cache result in Redis (TTL: 1h)
   ↓
9. Return result

⏱️ Total: ~1-2s
```

## Component Responsibilities

### API Layer (FastAPI)
- **Purpose**: HTTP interface, orchestration
- **Tech**: FastAPI + Uvicorn
- **Responsibilities**:
  - Request validation
  - Image preprocessing
  - Hash computation
  - Cache coordination
  - Response formatting
  - Metrics emission

### Cache Layer (Redis)
- **Purpose**: Fast result retrieval
- **Tech**: Redis (standalone)
- **Key Pattern**: `detection:{image_hash}`
- **TTL**: 3600s (1 hour)
- **Benefits**:
  - Avoid redundant inference
  - Reduce latency 20x
  - Lower compute costs

### Storage Layer (MinIO/S3)
- **Purpose**: Persistent image storage
- **Tech**: MinIO (local), S3 (cloud)
- **Bucket**: `vision-images`
- **Benefits**:
  - Audit trail
  - Reprocessing capability
  - Training data collection

### Inference Layer (YOLO)
- **Purpose**: Object detection
- **Tech**: YOLOv8 (Ultralytics)
- **Model**: yolov8n.pt (nano, 6MB)
- **Output**:
  - Detected classes
  - Bounding boxes
  - Confidence scores

### Monitoring Layer
- **Prometheus**: Metrics collection
- **Grafana**: Visualization
- **Metrics**:
  - Request rate
  - Latency (p50, p95, p99)
  - Error rate
  - Cache hit ratio
  - Pod CPU/memory

## Deployment Modes

### Local Development (Minikube)
```
Host Machine
├── API (Python) ─────→ Minikube
                        ├── Redis (NodePort 30379)
                        ├── MinIO (NodePort 30900)
                        └── Prometheus/Grafana
```

### Kubernetes Deployment (Minikube)
```
Minikube Cluster
├── vision-infra namespace
│   ├── Redis pods
│   └── MinIO pods
├── vision-app namespace
│   └── API pods (2-10 replicas)
└── vision-monitoring namespace
    ├── Prometheus
    └── Grafana
```

### Cloud Deployment (AWS EKS)
```
AWS EKS Cluster
├── vision-infra namespace
│   └── Redis (ElastiCache option)
├── vision-app namespace
│   └── API pods (with HPA)
└── External Services
    ├── S3 (storage)
    ├── CloudFront (CDN)
    └── ALB (load balancer)
```

## Scaling Strategy

### Horizontal Pod Autoscaling
```yaml
Trigger: CPU > 70%
Min Replicas: 2
Max Replicas: 10

Scaling behavior:
- Scale up:   +100% every 30s (aggressive)
- Scale down: -50% every 60s (conservative)
```

### Resource Limits
```yaml
Per Pod:
  Requests:
    CPU: 250m
    Memory: 512Mi
  Limits:
    CPU: 500m
    Memory: 1Gi

Max cluster capacity:
  10 pods × 500m = 5 CPU cores
  10 pods × 1Gi  = 10 GB RAM
```

## Data Flow Diagram

```
┌──────────┐
│  Client  │
└─────┬────┘
      │ POST /detect (multipart/form-data)
      ▼
┌──────────────┐
│  API Server  │
└──────┬───────┘
       │
       ├─ 1. Receive image
       ├─ 2. Compute SHA256 hash
       │
       ▼
┌──────────────┐
│    Redis     │◄──── GET detection:{hash}
└──────┬───────┘
       │
   ┌───┴───┐
   │ Hit?  │
   └───┬───┘
       │
    ┌──┴──┐
    │ YES │ → Return cached result ✓
    └─────┘
       │ NO
       ▼
┌──────────────┐
│ YOLO Model   │
│ (Inference)  │
└──────┬───────┘
       │
       ├─ 1. Run detection
       ├─ 2. Extract bounding boxes
       ├─ 3. Format results
       │
       ▼
┌──────────────┐
│   MinIO/S3   │◄──── PUT image
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    Redis     │◄──── SET detection:{hash} (TTL: 1h)
└──────────────┘
       │
       ▼
    Return result ✓
```

## Security Considerations

### Network Policies
```yaml
# API can access:
- Redis (port 6379)
- MinIO (port 9000)

# External access:
- Ingress → API only
- No direct access to Redis/MinIO
```

### Secrets Management
```yaml
# Stored in Kubernetes Secrets
- Redis password
- MinIO access keys
- S3 credentials
- API keys (future)
```

### RBAC (Future)
```
API Tokens
Rate Limiting
User Authentication
```

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| Latency (cached) | < 100ms | TBD |
| Latency (inference) | < 2s | TBD |
| Throughput | 100 req/s | TBD |
| Error rate | < 0.1% | TBD |
| Cache hit ratio | > 70% | TBD |
| Model accuracy | > 0.5 mAP | N/A |

## Tech Stack Rationale

| Component | Choice | Why? |
|-----------|--------|------|
| FastAPI | Web framework | Async, fast, auto docs |
| YOLOv8 | Detection model | SOTA, fast, easy to use |
| Redis | Cache | In-memory, fast, simple |
| MinIO | Storage (local) | S3-compatible, free |
| Kubernetes | Orchestration | Industry standard, scalable |
| Helm | Packaging | Templating, versioning |
| Helmfile | Orchestration | Multi-chart management |
| Prometheus | Metrics | Standard, powerful |
| Grafana | Visualization | Beautiful, flexible |

## Future Enhancements

### Phase 4: GitOps
- ArgoCD for declarative deployments
- Git as source of truth
- Auto-sync from repository

### Phase 5: Advanced Monitoring
- Distributed tracing (Jaeger)
- Log aggregation (Loki/ELK)
- Alerting (Alertmanager)

### Phase 6: Batch Processing
- Queue-based processing (Celery)
- Message broker (RabbitMQ/Kafka)
- Batch inference jobs

### Phase 7: Multi-Model Support
- Model versioning (MLflow)
- A/B testing
- Shadow deployments
- Canary releases

---

**Document Version:** 1.0  
**Last Updated:** February 12, 2026
