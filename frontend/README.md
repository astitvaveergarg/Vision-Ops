# VisionOps Frontend

Lightweight nginx-based frontend for VisionOps served as a separate Kubernetes pod.

---

## Architecture

```
ingress-nginx (External IP)
        │
        ▼
vision-frontend Pod (nginx:alpine, ~15MB image)
├── GET /           → serves index.html from /usr/share/nginx/html
├── GET /api/*      → proxy_pass → vision-api.vision-app.svc.cluster.local:8000/
└── GET /metrics    → (proxied via /api/metrics)
        │
        ▼ (ClusterIP only — not publicly directly accessible)
vision-api Pod (FastAPI + YOLOv8)
```

The frontend and backend are **separate Helm charts** deployed as separate pods:
- `charts/frontend/` → `vision-frontend` Helmfile release
- `charts/api/` → `vision-api` Helmfile release

---

## UI Features

- **Model Selector**: Choose from 5 YOLOv8 variants (nano → xlarge) per detection
- **Drag & Drop Upload**: Image upload with instant preview
- **Detection Canvas**: Bounding boxes drawn on the image with labels + confidence scores
- **Detection List**: All detected objects listed with class and confidence
- **Live Stats Dashboard**: Cache hit rate, total detections, stored images, avg inference time
- **System Health**: Redis, MinIO, model status indicators

---

## Access URLs

| Environment | URL |
|-------------|-----|
| **GKE (active)** | `http://<EXTERNAL-IP>/` |
| **API Docs (via proxy)** | `http://<EXTERNAL-IP>/api/docs` |
| **API Health** | `http://<EXTERNAL-IP>/api/health` |
| **Local port-forward** | `kubectl port-forward svc/vision-frontend 8080:80 -n vision-app` → `http://localhost:8080/` |
| **Docker Compose** | `http://localhost/` |

---

## Helm Chart Structure

```
charts/frontend/
├── Chart.yaml                    # name: vision-frontend, version: 1.0.0
├── values.yaml                   # defaults: backend FQDN, port, nginx settings
├── values-local.yaml             # ingress.enabled: false
├── values-dev.yaml               # ingress.enabled: true, pullPolicy: Always
├── values-prod.yaml              # replicaCount: 2, CDN header annotations
└── templates/
    ├── _helpers.tpl              # fullname, labels, selectorLabels helpers
    ├── deployment.yaml           # nginx deployment, mounts ConfigMap
    ├── service.yaml              # ClusterIP port 80
    ├── ingress.yaml              # Conditional on .Values.ingress.enabled
    └── configmap.yaml            # nginx.conf with /api/ proxy_pass
```

Key values (`charts/frontend/values.yaml`):
```yaml
backend:
  service: vision-api.vision-app.svc.cluster.local
  port: 8000

nginx:
  maxBodySize: 100m    # client_max_body_size (overridden per env)
  readTimeout: 300s    # proxy_read_timeout

ingress:
  enabled: false       # true in dev/prod via values-dev.yaml
```

---

## Docker Image

**Image**: `astitvaveergarg/vision-frontend:latest`  
**Built by**: `.github/workflows/frontend-build.yaml` (triggers on push)  
**Base**: `nginx:1.25-alpine`  
**Size**: ~15MB  
**Content**: `frontend/index.html` → `/usr/share/nginx/html/index.html`

After code changes:
```bash
git push origin feat/cpu-dockerfile-local
# CI builds new image in ~2-3 minutes
# Then restart pod to pull new image:
kubectl rollout restart deployment/vision-frontend -n vision-app
```

---

## nginx Configuration

The nginx config is managed as a Kubernetes ConfigMap (`charts/frontend/templates/configmap.yaml`).
Key routing rules:

```nginx
# Serve static files
location / {
    root /usr/share/nginx/html;
    try_files $uri $uri/ /index.html;
}

# Proxy API — strips /api/ prefix before forwarding
location /api/ {
    proxy_pass http://vision-api.vision-app.svc.cluster.local:8000/;
    client_max_body_size 100m;
    proxy_read_timeout 300s;
    add_header 'Access-Control-Allow-Origin' '*' always;
}
```

Note: `proxy_pass` ends with `/` which strips the `/api/` prefix.
`GET /api/detect` → forwarded as `GET /detect` to FastAPI.
