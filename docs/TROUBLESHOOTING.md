# Troubleshooting Guide - VisionOps

---

## Quick Diagnostics

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A
kubectl top nodes

# Application pods
kubectl get pods -n vision-app
kubectl get pods -n vision-infra
kubectl get pods -n vision-monitoring

# Events (most useful for diagnosing startup failures)
kubectl get events -n vision-app --sort-by='.lastTimestamp'
kubectl get events -n vision-infra --sort-by='.lastTimestamp'

# Logs
kubectl logs -f deployment/vision-api -n vision-app
kubectl logs -f deployment/vision-frontend -n vision-app

# API health
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/api/health
```

---

## Swagger UI Issues

### "Parser error on line 13 / does not specify a valid version field"

**Cause**: Swagger UI requests `GET /openapi.json` at absolute path. Without `root_path`, nginx serves `index.html` (HTML) instead of JSON.

**Fix** (already applied): `ROOT_PATH=/api` is set in `charts/api/values.yaml`.

**Verify**:
```bash
kubectl exec -n vision-app deployment/vision-api -- env | grep ROOT_PATH
# Expected: ROOT_PATH=/api
```

**If missing** (e.g. after manual kubectl override):
```bash
kubectl set env deployment/vision-api -n vision-app ROOT_PATH=/api
# Then redeploy properly via helmfile -e dev apply
```

**Access Swagger**:
- ✅ `http://<EXTERNAL-IP>/api/docs` — via nginx proxy (correct)
- ✅ `http://localhost:8000/docs` — via port-forward direct (also correct when ROOT_PATH is empty locally)
- ❌ `http://<EXTERNAL-IP>/docs` — not proxied by nginx (404)

---

## Pod Issues

### Pods Stuck in Pending

```bash
kubectl describe pod <pod-name> -n vision-app
# Read the Events section at the bottom
```

**Cause: Insufficient resources**
```bash
kubectl top nodes
# If CPU/memory exhausted:
kubectl scale deployment/vision-api -n vision-app --replicas=1
```

**Cause: PVC not bound**
```bash
kubectl get pvc -n vision-app
kubectl describe pvc <pvc-name> -n vision-app
# Check if storageClass exists
kubectl get storageclass
# For GKE dev, must be "standard" (not "gp3"):
# See charts/api/values-dev.yaml — storageClass: "standard"
```

**Cause: RWO PVC multi-attach (HPA scaled during model download)**
```bash
kubectl get pvc -n vision-app
# If Bound to one node but second pod tries to attach:
# Solution: keep autoscaling.enabled: false in dev
# Fix: delete the second pod; HPA will not recreate since autoscaling is off
```

---

### CrashLoopBackOff

```bash
kubectl logs <pod-name> -n vision-app --previous
```

**Cause: Secret not found**
```bash
# Check secrets exist in the RIGHT namespace
kubectl get secrets -n vision-app
kubectl get secrets -n vision-infra

# vision-api needs secrets in vision-app namespace
# vision-redis needs secrets in vision-infra namespace
# Both must exist — see k8s/secrets-dev.yaml.example

# Re-apply secrets
kubectl apply -f k8s/secrets-dev.yaml
kubectl rollout restart deployment/vision-api -n vision-app
```

**Cause: Cannot connect to Redis**
```bash
# Test Redis from inside cluster
kubectl run -it --rm redis-test --image=redis:alpine --restart=Never -n vision-app -- \
  redis-cli -h redis-master.vision-infra.svc.cluster.local -a YOUR_PASSWORD ping
# Expected: PONG

# Check Redis pod is running
kubectl get pods -n vision-infra | grep redis
```

**Cause: Cannot connect to MinIO**
```bash
# Check MinIO pod
kubectl get pods -n vision-infra | grep minio

# Test MinIO from inside cluster
kubectl run -it --rm minio-test --image=curlimages/curl --restart=Never -n vision-app -- \
  curl http://minio.vision-infra.svc.cluster.local:9000/minio/health/ready
# Expected: HTTP 200
```

**Cause: Model download failed (no internet)**
```bash
kubectl logs -n vision-app deployment/vision-api | grep -i "model\|download\|error"
# GKE nodes have internet access via Cloud NAT — should work
# Check Cloud NAT config in terraform/gcp/gke.tf
```

---

### ImagePullBackOff

```bash
kubectl describe pod <pod-name> -n vision-app | grep -A5 "Events"
```

**Cause: CI has not finished building the image yet**
- Check: https://github.com/astitvaveergarg/Vision-Ops/actions
- Wait for the workflow to complete

**Cause: Wrong image tag in values**
```bash
kubectl get deployment vision-api -n vision-app -o yaml | grep image
# Should be: astitvaveergarg/vision-api:latest (or branch-specific tag)
```

**Force re-pull** (pullPolicy: Always is set in dev):
```bash
kubectl rollout restart deployment/vision-api -n vision-app
kubectl rollout restart deployment/vision-frontend -n vision-app
```

---

## Networking Issues

### 502 Bad Gateway from nginx/ingress

```bash
# Check if vision-api pod is ready
kubectl get pods -n vision-app
kubectl describe pod -n vision-app | grep -A3 "Ready"

# Check nginx frontend logs
kubectl logs deployment/vision-frontend -n vision-app

# Check vision-api is reachable from frontend pod
kubectl exec -n vision-app deployment/vision-frontend -- \
  wget -qO- http://vision-api.vision-app.svc.cluster.local:8000/health
```

### 404 on /api/* routes

```bash
# Verify nginx ConfigMap has the /api/ location block
kubectl get configmap -n vision-app | grep nginx
kubectl describe configmap <nginx-configmap> -n vision-app
# Should show: location /api/ { proxy_pass http://vision-api...:8000/; }
```

### No External IP on ingress-nginx service

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# If EXTERNAL-IP is <pending> for >3 minutes:

# GKE: Check if LoadBalancer quota is hit
gcloud compute forwarding-rules list

# Check ingress-nginx pod logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### DNS resolution failure between namespaces

```bash
# Test DNS from vision-app namespace
kubectl run -it --rm dns-test --image=busybox --restart=Never -n vision-app -- \
  nslookup redis-master.vision-infra.svc.cluster.local
# Should resolve to ClusterIP of Redis service
```

---

## Storage Issues

### PVC Stuck in Pending

```bash
kubectl describe pvc -n vision-app
# Check "WaitForFirstConsumer" — normal if no pod scheduled yet
# Check "ProvisioningFailed" — wrong storage class

kubectl get storageclass
# GKE dev must use "standard" (not "gp3" which is AWS-only)
# Fix in charts/api/values-dev.yaml: storageClass: "standard"
```

### MinIO bucket operations failing

```bash
# Check MinIO logs
kubectl logs -n vision-infra deployment/minio

# Verify credentials match between MinIO chart and vision-api
kubectl get secret vision-minio-credentials -n vision-infra -o yaml
kubectl get secret vision-minio-credentials -n vision-app -o yaml
# rootUser and rootPassword values must match
```

---

## Performance Issues

### Slow first inference (>30s)

This is expected — first request triggers model download from Ultralytics CDN.  
Subsequent requests use the cached model on the PVC.

```bash
# Watch model download progress
kubectl logs -f -n vision-app deployment/vision-api | grep -i "model\|download"
```

### High inference latency

```bash
# Check resource usage
kubectl top pod -n vision-app
kubectl top nodes

# Check if CPU limit is too low (< 500m causes throttling)
kubectl describe pod -n vision-app | grep -A5 "Limits"

# Check Prometheus latency histogram
# http://localhost:3000 → Grafana → Explore
# histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m]))
```

### Redis not caching (cache_hits always 0)

```bash
# Test Redis write/read
kubectl exec -n vision-app deployment/vision-api -- \
  python -c "
import redis, os
r = redis.Redis(
  host=os.getenv('REDIS_HOST'),
  port=int(os.getenv('REDIS_PORT','6379')),
  password=os.getenv('REDIS_PASSWORD')
)
r.set('test', 'ok', ex=10)
print('Redis test:', r.get('test'))
"
```

---

## Helmfile / Helm Issues

### "Error: release not found"

```bash
# List installed releases
helm list -n vision-app
helm list -n vision-infra
helm list -n vision-monitoring

# Re-sync everything
helmfile -e dev sync
```

### "Error: rendered manifests contain a resource that already exists"

```bash
# Use apply instead of sync (idempotent)
helmfile -e dev apply

# Or force with --reset-values
helmfile -e dev sync --reset-values
```

### Secret "vision-redis-credentials" not found during Helmfile deploy

```bash
# Secrets must exist BEFORE helmfile runs
kubectl apply -f k8s/secrets-dev.yaml
# Then re-run
helmfile -e dev sync
```

---

## Emergency Procedures

### Full Cluster Reset (Dev)

```bash
# 1. Destroy all Helm releases
helmfile -e dev destroy

# 2. Delete PVCs (data will be lost)
kubectl delete pvc --all -n vision-app
kubectl delete pvc --all -n vision-infra
kubectl delete pvc --all -n vision-monitoring

# 3. Delete namespaces
kubectl delete namespace vision-app vision-infra vision-monitoring ingress-nginx

# 4. Wait for namespaces to terminate (~1-2 min)
kubectl get namespaces -w

# 5. Recreate everything
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring
kubectl create namespace ingress-nginx
kubectl apply -f k8s/secrets-dev.yaml
helmfile -e dev sync
```

### Rollback a Single Release

```bash
helm history vision-api -n vision-app
helm rollback vision-api <REVISION> -n vision-app
```

### Force Pod Restart

```bash
kubectl rollout restart deployment/vision-api -n vision-app
kubectl rollout restart deployment/vision-frontend -n vision-app
kubectl rollout status deployment/vision-api -n vision-app
kubectl rollout status deployment/vision-frontend -n vision-app
```
