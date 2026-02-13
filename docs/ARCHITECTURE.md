# 🏗️ VisionOps Architecture Documentation

> **Comprehensive architecture guide** - Design decisions, component interactions, and system behavior

---

## 📑 Table of Contents

- [System Overview](#system-overview)
- [Architecture Layers](#architecture-layers)
- [Component Deep Dive](#component-deep-dive)
- [Data Flow](#data-flow)
- [Deployment Architectures](#deployment-architectures)
- [Security Architecture](#security-architecture)
- [Scalability Design](#scalability-design)
- [High Availability](#high-availability)

---

## System Overview

VisionOps is a cloud-native ML inference platform built on Kubernetes, designed to serve YOLO object detection models at scale. The architecture emphasizes:

- **Horizontal Scalability**: Auto-scaling from 1 to 20+ pods
- **High Availability**: Multi-replica deployments with PodDisruptionBudgets
- **Performance**: Multi-layer caching (Redis + in-memory LRU)
- **Security**: Private clusters with CDN-only public access
- **Observability**: Complete metrics, logs, and traces

### Design Principles

1. **Stateless Services**: All application state stored externally (Redis/MinIO)
2. **Separation of Concerns**: Frontend, backend, data, and monitoring layers isolated
3. **Defense in Depth**: Multiple security layers (CDN → WAF → Internal LB → Pod)
4. **Infrastructure as Code**: Everything versioned and reproducible
5. **Environment Parity**: Same code/configs across local/dev/prod

---

## Architecture Layers

### 1️⃣ **Edge Layer** (Production Only)

**Components**: CloudFront / Azure Front Door + WAF

**Responsibilities**:
- TLS termination
- DDoS protection
- Rate limiting (2000 req/min AWS, 100 req/min Azure)
- Origin validation via custom headers
- Static asset caching
- Geographic distribution

**Traffic Flow**:
```
Internet → CDN (Cache Miss?) → Custom Header Validation → Internal LB
              ↓ (Cache Hit)
              User (from edge POP)
```

### 2️⃣ **Load Balancer Layer**

**Components**: AWS ALB / Azure Load Balancer (Internal)

**Responsibilities**:
- HTTPS → HTTP translation inside VPC
- Health check management
- Request routing to healthy pods
- Session affinity (if needed)
- Connection pooling

**Configuration**:
```yaml
# Internal LB (no public IP)
service.beta.kubernetes.io/aws-load-balancer-internal: "true"
service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
```

### 3️⃣ **Application Layer**

**Components**: API Pods (FastAPI + YOLOv8), Frontend Pods (Nginx)

**Responsibilities**:
- Request validation and parsing
- Model inference orchestration
- Result caching logic
- Metrics emission
- Error handling and logging

**Characteristics**:
- **Stateless**: No local data storage
- **Auto-scaled**: HPA based on CPU (70% target)
- **Resource-bounded**: Requests (500m CPU, 1Gi RAM) and Limits (2 CPU, 4Gi RAM)
- **Health-checked**: Liveness (HTTP /health) and Readiness (HTTP /ready) probes

### 4️⃣ **Data Layer**

**Components**: Redis (Cache), MinIO (Object Storage)

**Responsibilities**:

**Redis**:
- Detection result caching (TTL: 3600s)
- Session storage (if needed)
- Rate limiting counters
- Metrics aggregation

**MinIO**:
- Image persistence (input images)
- Detection result images (with bounding boxes)
- Model artifacts (if not baked into image)
- Backup storage

**Replication**:
- Redis: Master + 3 replicas (read scaling)
- MinIO: 4-node cluster with erasure coding (dev/prod)

### 5️⃣ **Observability Layer**

**Components**: Prometheus, Grafana, AlertManager

**Responsibilities**:
- Metrics collection (15s scrape interval)
- Dashboard visualization
- Alert evaluation and routing
- Log aggregation (if Loki added)

**Metrics Collected**:
- Infrastructure: CPU, memory, disk, network per pod/node
- Application: Request rate, latency, error rate (RED)
- ML: Inference duration, model load time, cache hit ratio
- Business: Detections per model, confidence distributions

---

## Component Deep Dive

### API Service (Backend)

**Technology**: FastAPI + Uvicorn + YOLOv8 (Ultralytics)

**Key Features**:

1. **Multi-Model Support**
   ```python
   class ModelManager:
       def __init__(self, cache_size=2):
           self.models = {}  # LRU cache
           self.cache_size = cache_size
       
       def load_model(self, model_name: str):
           if model_name not in self.models:
               if len(self.models) >= self.cache_size:
                   # Evict least recently used
                   self.models.popitem(last=False)
               self.models[model_name] = YOLO(f"{model_name}.pt")
           return self.models[model_name]
   ```

2. **Caching Strategy**
   - Level 1: Model cache (in-memory LRU, 2 models)
   - Level 2: Result cache (Redis, 1 hour TTL)
   - Cache key: `sha256(image_bytes + model_name)`

3. **Async Processing**
   ```python
   @app.post("/detect")
   async def detect(
       file: UploadFile,
       model: str = "yolov8n",
       cache_service: CacheService = Depends(get_cache)
   ):
       image_bytes = await file.read()  # Non-blocking
       cache_key = hashlib.sha256(image_bytes + model.encode()).hexdigest()
       
       # Check cache (async Redis call)
       cached = await cache_service.get(cache_key)
       if cached:
           return cached
       
       # Run inference
       result = detector.detect(image_bytes, model)
       
       # Store in cache (fire and forget)
       asyncio.create_task(cache_service.set(cache_key, result))
       
       return result
   ```

4. **Health Checks**
   - `/health`: Liveness (is service alive?)
     - Checks: Python process running, Redis connection, MinIO connection
   - `/ready`: Readiness (can it serve traffic?)
     - Checks: At least 1 model loaded, Redis writable, MinIO writable

### Frontend Service

**Technology**: Nginx 1.25 (Alpine)

**Responsibilities**:
- Serve static HTML/CSS/JS
- Reverse proxy to backend API
- Compress responses (gzip)
- Cache static assets

**Configuration Highlights**:
```nginx
server {
    listen 80;
    server_name _;
    
    # Static files
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }
    
    # API proxy
    location /api/ {
        proxy_pass http://vision-api:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    # Metrics endpoint
    location /metrics {
        proxy_pass http://vision-api:8000/metrics;
    }
}
```

### Redis Cache

**Deployment**: Bitnami Redis Helm chart

**Configuration**:
- **Master**: 1 pod (writes + reads)
- **Replicas**: 3 pods (reads only)
- **Persistence**: Enabled (RDB snapshots every 5 min)
- **Memory**: 2Gi per pod
- **Eviction**: `allkeys-lru` (evict least recently used when full)

**Use Cases**:
1. Detection result caching
2. Rate limiting (INCR + EXPIRE)
3. Session storage
4. Distributed locks (if needed)

### MinIO Storage

**Deployment**: Bitnami MinIO Helm chart

**Configuration**:
- **Mode**: Standalone (local/dev), Distributed (prod, 4 nodes)
- **Buckets**: `vision-uploads`, `vision-results`
- **Replication**: 2:2 erasure coding (can lose 2 disks)
- **Storage**: 10Gi (local), 50Gi (dev), 200Gi (prod)

**Access Pattern**:
```python
# Store uploaded image
s3_client.put_object(
    Bucket="vision-uploads",
    Key=f"{request_id}/{filename}",
    Body=image_bytes
)

# Store result image with bounding boxes
s3_client.put_object(
    Bucket="vision-results",
    Key=f"{request_id}/result.jpg",
    Body=result_image_bytes
)
```

### Prometheus + Grafana

**Prometheus**:
- **Scrape Interval**: 15 seconds
- **Retention**: 15 days
- **Storage**: 50Gi PVC
- **Targets**:
  - Kubernetes API server
  - Node exporter (all nodes)
  - kube-state-metrics
  - Application `/metrics` endpoints

**Grafana**:
- **Dashboards**: 5 pre-configured
  - Kubernetes Cluster Overview
  - Application Performance (RED metrics)
  - ML Inference Metrics
  - Redis Performance
  - MinIO Storage
- **Auth**: admin/prom-operator (default)
- **Data Source**: Prometheus (automatic)

---

## Data Flow

### Detection Request Flow (Uncached)

```
1. User uploads image via frontend
   ↓
2. Frontend POST /detect → API pod
   ↓
3. API: Generate cache key (SHA256)
   ↓
4. API: Check Redis cache → MISS
   ↓
5. API: Load model (from LRU cache or disk)
   ↓
6. API: Run inference (~50-600ms depending on model)
   ↓
7. API: Store result in Redis (async)
   ↓
8. API: Store images in MinIO (async)
   ↓
9. API: Return JSON response
   ↓
10. Frontend: Render bounding boxes
```

**Latency Breakdown**:
- Network (user → CDN → LB): 50-100ms
- API processing (pre-inference): 5-10ms
- Model loading (if not cached): 2-30s (first time only)
- Inference: 50-600ms (model-dependent)
- Cache storage: <5ms (async)
- Response serialization: 5-10ms
- **Total**: ~100-700ms (after model cached)

### Detection Request Flow (Cached)

```
1. User uploads image via frontend
   ↓
2. Frontend POST /detect → API pod
   ↓
3. API: Generate cache key (SHA256)
   ↓
4. API: Check Redis cache → HIT
   ↓
5. API: Return cached result
   ↓
6. Frontend: Render bounding boxes
```

**Latency**: ~50-100ms (10x faster!)

---

## Deployment Architectures

### Local (Minikube)

```
┌─────────────────────────────────────┐
│         Laptop / Workstation         │
│  ┌───────────────────────────────┐  │
│  │        Minikube VM             │  │
│  │  ┌──────────┐  ┌──────────┐   │  │
│  │  │ Frontend │  │   API    │   │  │
│  │  │  (1 pod) │  │ (1 pod)  │   │  │
│  │  └──────────┘  └──────────┘   │  │
│  │  ┌──────────┐  ┌──────────┐   │  │
│  │  │  Redis   │  │  MinIO   │   │  │
│  │  │(master+0)│  │(standalone)│  │  │
│  │  └──────────┘  └──────────┘   │  │
│  └───────────────────────────────┘  │
│         NodePort / Port-forward      │
└─────────────────────────────────────┘
```

**Characteristics**:
- Single-node cluster
- HostPath storage
- No HA, no CDN
- For development/testing only

### Dev (Cloud Cluster)

```
┌──────────────────────────────────────────┐
│           Private VPC / VNet              │
│  ┌────────────────────────────────────┐  │
│  │      Kubernetes Cluster (Private)   │  │
│  │  ┌────────┐  ┌────────┐            │  │
│  │  │  Node1 │  │  Node2 │            │  │
│  │  │┌──────┐│  │┌──────┐│            │  │
│  │  ││ API  ││  ││ API  ││            │  │
│  │  │└──────┘│  │└──────┘│            │  │
│  │  │┌──────┐│  │┌──────┐│            │  │
│  │  ││Redis ││  ││MinIO ││            │  │
│  │  │└──────┘│  │└──────┘│            │  │
│  │  └────────┘  └────────┘            │  │
│  │         ↑                            │  │
│  │    Internal LB                       │  │
│  └────────────────────────────────────┘  │
│              ↑                            │
│         VPN Gateway                       │
└──────────────────────────────────────────┘
          ↑
    Developer (VPN)
```

**Characteristics**:
- 2-3 nodes
- Private API endpoint only
- Access via VPN/Bastion
- GP3/Premium disk storage
- HPA: 2-5 pods

### Production (Cloud Cluster)

```
Internet Users
      ↓
┌─────────────────────────────────┐
│   CloudFront / Azure Front Door  │
│         (Global CDN)             │
│  • TLS Termination               │
│  • DDoS Protection               │
│  • WAF Rules (Rate limit, OWASP) │
│  • Custom Header Validation      │
└─────────────────────────────────┘
      ↓ (validates X-Custom-Header)
┌────────────────────────────────────────┐
│      Private VPC / VNet (Multi-AZ)     │
│  ┌──────────────────────────────────┐  │
│  │     EKS / AKS Cluster (HA)       │  │
│  │  ┌────────┐  ┌────────┐  ┌─────┐│  │
│  │  │  AZ-1  │  │  AZ-2  │  │ AZ-3││  │
│  │  │┌──────┐│  │┌──────┐│  │┌───┐││  │
│  │  ││API(5)││  ││API(5)││  ││API││││  │
│  │  │└──────┘│  │└──────┘│  │└───┘││  │
│  │  │┌──────┐│  │┌──────┐│  │     ││  │
│  │  ││Redis ││  ││Redis ││  │     ││  │
│  │  ││Master││  ││Replica│  │     ││  │
│  │  │└──────┘│  │└──────┘│  │     ││  │
│  │  └────────┘  └────────┘  └─────┘│  │
│  │         ↑          ↑         ↑   │  │
│  │         └─── Internal LB ────┘   │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

**Characteristics**:
- 3-6 nodes across multiple AZs
- Private cluster (no public API)
- CDN-only public access
- GP3/Premium disk with backups
- HPA: 3-20 pods
- PDB: min 2 pods always running
- Anti-affinity: Spread across AZs

---

## Security Architecture

### Defense in Depth

**Layer 1: Edge (CDN + WAF)**
- TLS 1.2+ only
- DDoS protection (AWS Shield, Azure DDoS)
- Rate limiting (per IP/per client)
- SQL injection blocking
- XSS prevention
- Custom header validation

**Layer 2: Network (VPC/VNet)**
- Private subnets (no internet gateway)
- NAT gateway for egress only
- Security groups / NSGs (allow HTTP/HTTPS only)
- VPN-only management access

**Layer 3: Cluster (Kubernetes)**
- Private API endpoint
- RBAC enabled (role-based access)
- NetworkPolicies (restrict pod-to-pod)
- PodSecurityPolicies (no privileged, no hostPath)

**Layer 4: Application (Pods)**
- Non-root containers (UID 1000)
- Read-only root filesystem
- Secrets via Kubernetes Secrets
- No hard-coded credentials
- Request validation (FastAPI)

### Secrets Management

**Storage**:
- Kubernetes Secrets (base64 encoded at rest)
- AWS Secrets Manager / Azure Key Vault (for Terraform)

**Access**:
- Mounted as environment variables or files
- RBAC restricts access to specific service accounts
- Rotation policy (manual for now, automated in future)

### Network Policies

```yaml
# Deny all by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

# Allow API → Redis
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-to-redis
spec:
  podSelector:
    matchLabels:
      app: vision-api
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
```

---

## Scalability Design

### Horizontal Scaling (HPA)

**Trigger**: CPU utilization > 70%

**Behavior**:
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
  minReplicas: 3  # prod
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50  # Scale up by 50% each time
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10  # Scale down slowly (10% at a time)
        periodSeconds: 60
```

**Scale-up**: Fast (50% increase every minute)  
**Scale-down**: Slow (10% decrease every minute, wait 5 min)

### Vertical Considerations

**Resource Requests/Limits**:
```yaml
resources:
  requests:
    memory: "1Gi"    # Minimum (1 model + overhead)
    cpu: "500m"      # 0.5 CPU cores
  limits:
    memory: "4Gi"    # Max (2 models + inference)
    cpu: "2000m"     # 2 CPU cores
```

**Why these values?**
- YOLOv8n model: ~6MB
- YOLOv8x model: ~136MB
- PyTorch overhead: ~500MB
- Inference temp memory: ~500MB-1GB
- Total: 1-2GB typical, 4GB safe max

### Capacity Planning

**Single Pod Capacity** (c5.2xlarge / F8s_v2):
- YOLOv8n: ~20 req/sec
- YOLOv8s: ~10 req/sec
- YOLOv8m: ~5 req/sec
- YOLOv8l: ~3 req/sec
- YOLOv8x: ~1.5 req/sec

**Example**: 100 req/sec with YOLOv8n
- Required pods: 100 / 20 = 5 pods minimum
- With HPA: Set min=5, max=15 (3x headroom)
- Cost: 5 pods * ~$100/month = $500/month base

---

## High Availability

### Pod Disruption Budgets

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: vision-api-pdb
spec:
  minAvailable: 2  # Always keep 2 pods running
  selector:
    matchLabels:
      app: vision-api
```

**Prevents**:
- All pods going down during node drains
- All pods restarting simultaneously
- Cluster upgrades breaking service

### Anti-Affinity Rules

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: vision-api
        topologyKey: topology.kubernetes.io/zone
```

**Effect**: Spreads pods across availability zones

### Rolling Updates

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Create 1 extra pod during update
    maxUnavailable: 0  # Never go below desired count
```

**Deployment Process**:
1. Create new pod with new version
2. Wait for health checks to pass
3. Route traffic to new pod
4. Terminate old pod
5. Repeat until all pods updated

**Result**: Zero-downtime deployments

---

## Performance Optimizations

### 1. Multi-Layer Caching

**L1 Cache (In-memory LRU)**:
- Models: 2 most recent
- Hit rate: ~80% (most users stick to 1-2 models)
- Eviction: LRU (least recently used)

**L2 Cache (Redis)**:
- Detection results: 1 hour TTL
- Hit rate: ~60% (repeated images common)
- Memory: 2GB Redis = ~10,000 cached results

**L3 Cache (CDN)**:
- Static assets: HTML, CSS, JS
- Hit rate: ~95%
- Reduces origin load significantly

### 2. Async Processing

**Non-blocking operations**:
- File uploads (chunked)
- Redis writes (fire and forget)
- MinIO uploads (background task)
- Metrics recording (async)

**Result**: API latency dominated by inference, not I/O

### 3. Connection Pooling

**Redis**:
```python
redis_pool = redis.ConnectionPool(
    host="redis-master",
    port=6379,
    max_connections=50,
    decode_responses=True
)
```

**MinIO**:
```python
s3_client = boto3.client(
    's3',
    config=Config(
        max_pool_connections=50,
        retries={'max_attempts': 3}
    )
)
```

**Benefit**: Reuse connections, reduce handshake overhead

---

## Monitoring Architecture

### Metrics Collection

```
┌─────────────┐
│   API Pods  │ ──── /metrics ────┐
└─────────────┘                    │
┌─────────────┐                    │
│  Redis Pods │ ──── /metrics ────┤
└─────────────┘                    ├──→ Prometheus
┌─────────────┐                    │     (scrape every 15s)
│ MinIO Pods  │ ──── /metrics ────┤
└─────────────┘                    │         ↓
┌─────────────┐                    │    ┌──────────┐
│ Node Export │ ──── /metrics ────┘    │ Grafana  │
└─────────────┘                         └──────────┘
```

### Alert Rules

**Critical Alerts** (immediate response):
- Any pod crash looping
- API error rate > 10%
- Inference latency p95 > 5 seconds
- Redis/MinIO unavailable

**Warning Alerts** (investigate within 1 hour):
- API error rate > 5%
- Inference latency p95 > 2 seconds
- Cache hit ratio < 40%
- Disk usage > 80%

---

## Design Decisions & Trade-offs

### Why Kubernetes?

**Pros**:
- Horizontal scaling (HPA)
- Self-healing (restarts failed pods)
- Rolling updates (zero downtime)
- Multi-cloud portability
- Rich ecosystem (Helm, Prometheus, etc.)

**Cons**:
- Complexity (learning curve)
- Resource overhead (~20% for K8s overhead)
- Debugging harder than VMs

**Verdict**: Worth it for production ML at scale

### Why Redis + MinIO vs Just S3?

**Redis**:
- Low latency (< 1ms) for cache hits
- In-network (no internet egress)
- Atomic operations (INCR for rate limiting)

**MinIO**:
- S3-compatible API (easy migration)
- On-premise option (data residency)
- Lower cost than S3 for high throughput

**If scale > 1000 req/sec**: Migrate to managed Redis (ElastiCache) + S3

### Why Private Cluster?

**Benefits**:
- Attack surface reduced (no public API)
- Compliance-friendly (PCI-DSS, HIPAA)
- Cost savings (no internet data transfer from API)

**Drawbacks**:
- VPN required for management (adds friction)
- CDN essential for production access
- Slightly slower development iteration

**Verdict**: Security and compliance outweigh inconvenience

---

## Future Enhancements

1. **GPU Support**: Add NVIDIA GPU node pool for faster inference
2. **Model Versioning**: A/B testing different YOLO versions
3. **Async API**: WebSocket for real-time streaming
4. **Batching**: Group multiple images per inference call
5. **Auto-tuning**: Optimize HPA thresholds based on historical data
6. **Multi-Region**: Deploy to multiple AWS regions for lower latency
7. **CI/CD**: Automated canary deployments with rollback

---

## Conclusion

VisionOps demonstrates a production-grade ML inference architecture with:
- ✅ Scalability (1 to 20+ pods)
- ✅ Security (private cluster + CDN)
- ✅ Performance (multi-layer caching)
- ✅ Reliability (HA, PDB, rolling updates)
- ✅ Observability (Prometheus + Grafana)

The architecture balances complexity with maintainability, making it suitable for real-world ML deployment scenarios.

---

**Last Updated**: February 13, 2026  
**Author**: Astitva Veer Garg
