# API Reference - VisionOps

> All API calls go through the nginx reverse proxy. The base path is `/api/`.

---

## Base URLs

| Environment | URL |
|-------------|-----|
| **GKE (active)** | `http://<EXTERNAL-IP>/api/` |
| **Local Docker Compose** | `http://localhost:8000/` (direct, no nginx) |
| **Port-forward** | `kubectl port-forward svc/vision-api 8000:8000 -n vision-app` → `http://localhost:8000/` |

**Interactive docs**:
- Swagger UI: `http://<EXTERNAL-IP>/api/docs`
- ReDoc: `http://<EXTERNAL-IP>/api/redoc`

> **Note on root_path**: FastAPI is configured with `ROOT_PATH=/api` (env var in `charts/api/values.yaml`).
> This ensures Swagger UI loads `openapi.json` via `/api/openapi.json` — correctly proxied by nginx.
> Without this, Swagger would try to load `/openapi.json` which nginx serves as `index.html` → YAML parser error.

---

## Endpoints

### GET /api/

Root endpoint — basic service info.

**Response 200:**
```json
{
  "service": "VisionOps API",
  "status": "healthy",
  "version": "1.0.0"
}
```

---

### GET /api/health

Liveness probe — checks service and all dependencies.

**Response 200:**
```json
{
  "status": "healthy",
  "redis": true,
  "minio": true,
  "model": true
}
```

**Response 200 (degraded):**
```json
{
  "status": "healthy",
  "redis": false,
  "minio": true,
  "model": true
}
```

**Use case**: Kubernetes liveness probe (`initialDelaySeconds: 30`, `periodSeconds: 10`)

---

### GET /api/models

List all available YOLO model variants.

**Response 200:**
```json
{
  "models": ["yolov8n", "yolov8s", "yolov8m", "yolov8l", "yolov8x"]
}
```

---

### POST /api/detect

Detect objects in an uploaded image.

**Request** (`multipart/form-data`):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `file` | file | Yes | — | Image file (JPG, PNG, WEBP, max 100MB via nginx) |
| `model` | string | No | `yolov8n` | Model ID: `yolov8n`, `yolov8s`, `yolov8m`, `yolov8l`, `yolov8x` |

**Example (via nginx proxy):**
```bash
# Via GKE external IP (nginx proxy)
curl -X POST http://<EXTERNAL-IP>/api/detect \
  -F "file=@photo.jpg" \
  -F "model=yolov8s"

# Via port-forward (direct to API pod)
curl -X POST http://localhost:8000/detect \
  -F "file=@photo.jpg" \
  -F "model=yolov8s"
```

**Response 200:**
```json
{
  "detections": [
    {
      "class": "person",
      "confidence": 0.92,
      "bbox": {"x1": 100, "y1": 50, "x2": 300, "y2": 400}
    },
    {
      "class": "car",
      "confidence": 0.87,
      "bbox": {"x1": 400, "y1": 200, "x2": 650, "y2": 380}
    }
  ],
  "model_id": "yolov8n",
  "inference_time_ms": 145.3,
  "cached": false,
  "image_hash": "a3f1b2c4d5e6f7a8...",
  "storage_url": "http://minio.vision-infra.svc.cluster.local:9000/vision-images/photo.jpg",
  "count": 2
}
```

**Cache behaviour:**
- Cache key: `sha256(image_bytes) + ":" + model_id`
- Cache TTL: 3600 seconds (configurable via `CACHE_TTL` env var)
- Second identical request returns same response with `"cached": true`

**Response 422** (validation error — unsupported file type or missing field):
```json
{
  "detail": [{"loc": ["body", "file"], "msg": "field required", "type": "value_error.missing"}]
}
```

**Response 503** (dependencies down):
```json
{"detail": "Service temporarily unavailable"}
```

---

### GET /api/stats

Service statistics for dashboard display.

**Response 200:**
```json
{
  "cache": {
    "hits": 142,
    "misses": 28,
    "total_keys": 28
  },
  "storage": {
    "bucket": "vision-images",
    "objects": 28,
    "healthy": true
  },
  "model": {
    "default": "yolov8n",
    "loaded_models": ["yolov8n"],
    "cache_size": 2
  }
}
```

---

### GET /api/metrics

Prometheus metrics in text format (scraped by Prometheus every 30s).

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{endpoint="/detect",method="POST",status="200"} 142.0
http_requests_total{endpoint="/health",method="GET",status="200"} 1820.0

# HELP inference_duration_seconds YOLO inference duration
# TYPE inference_duration_seconds histogram
inference_duration_seconds_bucket{le="0.05"} 2.0
inference_duration_seconds_bucket{le="0.1"} 5.0
inference_duration_seconds_bucket{le="0.25"} 98.0
inference_duration_seconds_bucket{le="0.5"} 138.0
inference_duration_seconds_bucket{le="1.0"} 142.0
inference_duration_seconds_bucket{le="+Inf"} 142.0
inference_duration_seconds_sum 28.45
inference_duration_seconds_count 142.0

# HELP cache_hits_total Cache hits
# TYPE cache_hits_total counter
cache_hits_total 114.0

# HELP cache_misses_total Cache misses
# TYPE cache_misses_total counter
cache_misses_total 28.0
```

---

## Model Reference

| Model ID | Parameters | Speed (CPU) | mAP50-95 | Best Use |
|----------|-----------|-------------|----------|----------|
| `yolov8n` | 3.2M | ~145ms | 37.3 | Real-time, low resource |
| `yolov8s` | 11.2M | ~280ms | 44.9 | Balanced speed/accuracy |
| `yolov8m` | 25.9M | ~520ms | 50.2 | Good accuracy |
| `yolov8l` | 43.7M | ~850ms | 52.9 | High accuracy |
| `yolov8x` | 68.2M | ~1200ms | 53.9 | Maximum accuracy |

> Speeds measured on `e2-standard-4` (4 vCPU, 16GB RAM). First request per model is slower (download + load from PVC).

---

## Error Codes

| Code | Meaning | Typical Cause | Fix |
|------|---------|--------------|-----|
| `200` | OK | — | — |
| `422` | Validation error | Wrong field names or types | Check request format |
| `500` | Internal error | Model exception, unexpected error | Check `kubectl logs` |
| `502` | Bad gateway | nginx can't reach vision-api | Check vision-api pod readiness |
| `503` | Service unavailable | Redis/MinIO down or model not loaded | Check vision-infra pods |

---

## Prometheus Queries (PromQL)

```promql
# Request rate (req/sec, 5-min window)
rate(http_requests_total{endpoint="/detect"}[5m])

# P95 inference latency
histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m]))

# Cache hit ratio (%)
cache_hits_total / (cache_hits_total + cache_misses_total) * 100

# Error rate (%)
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100
```
