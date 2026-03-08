# Architecture - VisionOps

---

## System Overview

VisionOps is a cloud-native ML inference platform built on Kubernetes. The architecture separates the frontend (nginx) and backend (FastAPI + YOLOv8) into distinct Helm charts and pods, with ingress handled exclusively through the frontend proxy.

### Core Principles

1. **Stateless API**: All persistent state in Redis (cache) and MinIO (storage)
2. **Frontend/Backend Split**: Independent scaling, smaller attack surface for each component
3. **Environment Parity**: Same Helm charts everywhere — only `values-<env>.yaml` differs
4. **Infrastructure as Code**: All provisioning via Terraform + Helmfile
5. **Runtime Model Loading**: YOLO weights downloaded at startup onto a PVC (not baked into image)

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (GKE vision-dev-gke / EKS / AKS)           │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │  ingress-nginx  │ ← External LoadBalancer IP                │
│  │  Namespace      │                                           │
│  └────────┬────────┘                                           │
│           │  routes /* → vision-frontend:80                    │
│           ▼                                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  vision-app Namespace                                    │  │
│  │                                                          │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │  vision-frontend Pod (nginx:alpine, 15MB)        │    │  │
│  │  │  ┌─────────────────────────────────────────┐    │    │  │
│  │  │  │  nginx.conf (from ConfigMap)             │    │    │  │
│  │  │  │  location /         → serve index.html   │    │    │  │
│  │  │  │  location /api/     → proxy_pass :8000/  │    │    │  │
│  │  │  └──────────────────┬──────────────────────┘    │    │  │
│  │  └──────────────────── │ ─────────────────────────┘    │  │
│  │           ClusterIP    │  vision-api:8000               │  │
│  │           ┌────────────▼───────────────────────────┐   │  │
│  │           │  vision-api Pod (FastAPI + YOLOv8)     │   │  │
│  │           │  - ROOT_PATH=/api                      │   │  │
│  │           │  - No Ingress (ClusterIP only)         │   │  │
│  │           │  - Mounts PVC at /app/models/          │   │  │
│  │           └──────────┬──────────────────┬──────────┘   │  │
│  └─────────────────────  │  ────────────── │ ────────────┘  │
│                          │                 │                  │
│  ┌───────────────────────▼─────────────────▼──────────────┐  │
│  │  vision-infra Namespace                                 │  │
│  │  ┌──────────────────┐   ┌──────────────────────────┐   │  │
│  │  │  Redis Master    │   │  MinIO                   │   │  │
│  │  │  + 0-3 replicas  │   │  (object storage)        │   │  │
│  │  │  Cache TTL 3600s │   │  bucket: vision-images   │   │  │
│  │  └──────────────────┘   └──────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  vision-monitoring Namespace                            │  │
│  │  Prometheus ←─── scrapes /api/metrics every 30s ───────│──┤
│  │  Grafana ←─────── queries Prometheus ──────────────────┘  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Deep Dive

### vision-frontend (Nginx, 15MB)

**Chart**: `charts/frontend/`  
**Image**: `astitvaveergarg/vision-frontend:latest`  
**Namespace**: `vision-app`

Responsibilities:
- Serve `index.html` static UI (HTML5 + Tailwind CSS + Vanilla JS)
- Reverse proxy all `/api/*` requests to `vision-api.vision-app.svc.cluster.local:8000/`
- Handle CORS headers for API responses
- Gzip compression for static assets

Key nginx.conf settings:
```nginx
location / {
    root /usr/share/nginx/html;
    try_files $uri $uri/ /index.html;
}

location /api/ {
    proxy_pass http://vision-api.vision-app.svc.cluster.local:8000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_read_timeout 300s;
    client_max_body_size 100m;  # configurable via values
    add_header 'Access-Control-Allow-Origin' '*' always;
}
```

Note how `/api/` → proxy strips the prefix: `GET /api/detect` becomes `GET /detect` on the backend.

---

### vision-api (FastAPI + YOLOv8, 4.5GB)

**Chart**: `charts/api/`  
**Image**: `astitvaveergarg/vision-api:latest`  
**Namespace**: `vision-app`  
**Service**: ClusterIP only (no Ingress)

Key environment variables:
```
ROOT_PATH=/api          # FastAPI root_path — fixes Swagger UI openapi.json URL
REDIS_HOST=redis-master.vision-infra.svc.cluster.local
REDIS_PORT=6379
REDIS_PASSWORD=<from secretKeyRef vision-redis-credentials>
MINIO_ENDPOINT=minio.vision-infra.svc.cluster.local:9000
MINIO_ACCESS_KEY=<from secretKeyRef vision-minio-credentials>
MINIO_SECRET_KEY=<from secretKeyRef vision-minio-credentials>
DEFAULT_MODEL_ID=yolov8n
CACHE_TTL=3600
```

**ModelManager (LRU)**:
- Keeps up to 2 YOLO models loaded in memory simultaneously
- Evicts least-recently-used model when cache is full
- Models downloaded from Ultralytics on first use, cached on PVC `/app/models/`

**Caching Strategy**:
- Cache key: `sha256(image_bytes) + ":" + model_id`
- Redis `SET` with `EX 3600` (1 hour TTL)
- Cache hit: skip inference, return cached result immediately

**PVC**: `ReadWriteOnce`, 10Gi, storageClass `standard` (dev) / `premium-rwo` (prod)
- Stores downloaded model weights so they survive pod restarts
- **This is why `autoscaling.enabled=false` in dev** — RWO PVC can only attach to one node at a time; if HPA scales to 2 replicas during the initial model download CPU spike, the second pod can't mount the PVC

---

### Redis (Bitnami chart)

**Namespace**: `vision-infra`  
**Secret**: `vision-redis-credentials` (key: `password`)  
**Dev storage**: `standard` 8Gi  
**Prod storage**: `premium-rwo` 8Gi

Used for:
- Detection result caching (primary use)
- Rate limiting counters (future)

---

### PostgreSQL (Bitnami chart)

**Namespace**: `vision-infra`  
**Secret**: `vision-postgres-credentials` (keys: `username`, `password` stored in `vision-app` namespace)  
**Database**: `visiondb`  
**Port**: `5432` (ClusterIP service)

This relational database will store authentication data, model registry metadata and inference job history. It is optional on local dev but enabled in the cloud environment starting with Phase 1.

Later phases will introduce Alembic migrations and application code that depends on this service.

---

### MinIO (Bitnami chart)

**Namespace**: `vision-infra`  
**Secret**: `vision-minio-credentials` (keys: `rootUser`, `rootPassword`)  
**Bucket**: `vision-images`  
**Dev storage**: `standard` 10Gi  
**Prod storage**: `premium-rwo` 50Gi

Used for:
- Persistent storage of uploaded images

---

### kube-prometheus-stack (Monitoring)

**Namespace**: `vision-monitoring`  
**Secret**: `vision-grafana-credentials` (keys: `admin-user`, `admin-password`)  
**Dev storage**: `standard` 10Gi (Prometheus), 5Gi (Grafana)

Components:
- **Prometheus**: Scrapes `/api/metrics` every 30s via ServiceMonitor
- **Grafana**: Dashboards for cluster health + application metrics
- **AlertManager**: Alert routing (configured post-deploy)
- **node-exporter**: Disabled in local env (causes issues in Minikube)

---

## Helm Releases (Helmfile)

`helmfile.yaml.gotmpl` orchestrates 6 releases in order:

| Release | Chart | Namespace | Condition |
|---------|-------|-----------|-----------|
| `ingress-nginx` | ingress-nginx/ingress-nginx 4.10.1 | ingress-nginx | always |
| `vision-redis` | charts/infrastructure/redis | vision-infra | always |
| `vision-minio` | charts/infrastructure/minio | vision-infra | always |
| `vision-prometheus` | charts/monitoring/prometheus | vision-monitoring | always |
| `vision-api` | charts/api | vision-app | always |
| `vision-frontend` | charts/frontend | vision-app | `frontend.enabled` |

Dependencies:
- `vision-api` needs: redis, minio (infra layer)
- `vision-frontend` needs: `vision-app/vision-api`

---

## Kubernetes Secrets

All credentials are stored as Kubernetes Secrets and injected via `secretKeyRef` (never hardcoded in values).

| Secret name | Namespace | Keys | Used by |
|-------------|-----------|------|---------|
| `vision-redis-credentials` | `vision-infra` | `password` | Redis chart |
| `vision-redis-credentials` | `vision-app` | `password` | vision-api pod |
| `vision-minio-credentials` | `vision-infra` | `rootUser`, `rootPassword` | MinIO chart |
| `vision-minio-credentials` | `vision-app` | `rootUser`, `rootPassword` | vision-api pod |
| `vision-grafana-credentials` | `vision-monitoring` | `admin-user`, `admin-password` | Grafana |

> Secrets must exist in **both** `vision-infra` and `vision-app` namespaces because `secretKeyRef` is namespace-scoped.
> Templates in `k8s/secrets-*.yaml.example` show the exact structure.

---

## Data Flow

### First Request (Cache Miss)

```
Browser → nginx ingress → vision-frontend nginx
  → POST /api/detect → vision-api:8000/detect
    → sha256(image) + model_id → Redis GET → miss
    → YOLO model load/get (from PVC or LRU cache)
    → YOLO inference → detections[]
    → MinIO PUT image
    → Redis SET result (TTL 3600)
    → return JSON response
  ← nginx proxies response back
← Browser receives detections
```

### Subsequent Request (Cache Hit)

```
Browser → nginx ingress → vision-frontend nginx
  → POST /api/detect → vision-api:8000/detect
    → sha256(image) + model_id → Redis GET → HIT
    → return cached JSON (cached: true)
  ← ~5ms response time
```

---

## Production Architecture (AWS/Azure)

For production deployments the architecture adds a CDN layer:

```
Internet → CloudFront (AWS) / Azure Front Door
            └── WAF rules (rate limit, OWASP)
            └── Custom origin header validation
            └── TLS termination
                    │
                    ▼
            Internal Load Balancer (no public IP)
                    │
                    ▼
            ingress-nginx → vision-frontend → vision-api
```

- `vision-api` pods: 3-20 replicas (HPA, CPU 70%)
- `vision-frontend` pods: 2 replicas (availability)
- `podDisruptionBudget: minAvailable: 1` for zero-downtime upgrades
- `podAntiAffinity: preferredDuringScheduling` spreads pods across nodes

---

## Security Model

| Layer | Control | Implementation |
|-------|---------|----------------|
| Edge | WAF, DDoS, rate limiting | CloudFront+WAF / Front Door+WAF / Cloud Armor |
| Network | CDN-only origin access | Custom header validation |
| K8s Ingress | Single entry point | ingress-nginx, TLS |
| Service | No public backend | vision-api ClusterIP only |
| Pod | Non-root execution | `runAsUser: 1000`, `runAsNonRoot: true` |
| Filesystem | Read-only root | `readOnlyRootFilesystem: false` (model writes to PVC) |
| Secrets | No hardcoded credentials | `secretKeyRef` from K8s Secrets |
| Capabilities | Dropped | `capabilities.drop: [ALL]` |
