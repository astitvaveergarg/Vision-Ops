# 🔧 VisionOps Troubleshooting Guide

> **Comprehensive troubleshooting reference** - Common issues, diagnostics, and solutions

---

## 📑 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Pod Issues](#pod-issues)
- [Networking Issues](#networking-issues)
- [Storage Issues](#storage-issues)
- [Performance Issues](#performance-issues)
- [Application Errors](#application-errors)
- [Infrastructure Issues](#infrastructure-issues)
- [Monitoring & Logging](#monitoring--logging)
- [Emergency Procedures](#emergency-procedures)

---

## Quick Diagnostics

### Health Check Commands

```bash
# Overall cluster health
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl top pods -A

# Application health
kubectl get pods -n vision-app
kubectl logs -f deployment/vision-api -n vision-app
kubectl describe deployment/vision-api -n vision-app

# Test API
curl http://localhost:8000/health
curl http://localhost:8000/ready
```

### Common Commands

```bash
# Get pod status
kubectl get pods -n vision-app -o wide

# View pod logs
kubectl logs <pod-name> -n vision-app

# Previous logs (if crashed)
kubectl logs <pod-name> -n vision-app --previous

# Tail logs
kubectl logs -f <pod-name> -n vision-app

# Shell into pod
kubectl exec -it <pod-name> -n vision-app -- /bin/bash

# Check events
kubectl get events -n vision-app --sort-by='.lastTimestamp'

# Describe resource (detailed info)
kubectl describe pod <pod-name> -n vision-app
```

---

## Pod Issues

### Pods Stuck in Pending

**Symptoms**:
- Pods show `Pending` status
- Application not starting

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n vision-app

# Look for:
# - "Insufficient cpu" or "Insufficient memory"
# - "no nodes available"
# - "FailedScheduling" events
```

**Common Causes & Solutions**:

#### 1. Insufficient Resources

**Cause**: Node doesn't have enough CPU/memory

```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Solution 1: Scale down replicas
kubectl scale deployment/vision-api -n vision-app --replicas=1

# Solution 2: Increase node capacity (cloud)
# AWS: Increase desired size in ASG
# Azure: Scale node pool
az aks scale --resource-group vision-prod-rg \
  --name vision-prod-aks --node-count 5
```

#### 2. PVC Not Bound

**Cause**: PersistentVolumeClaim waiting for volume

```bash
# Check PVC status
kubectl get pvc -n vision-infra

# Solution: Check storage class exists
kubectl get storageclass

# For Minikube: Verify storage provisioner
minikube addons enable storage-provisioner
```

#### 3. Node Selector Mismatch

**Cause**: Pod requires specific node labels

```bash
# Check node labels
kubectl get nodes --show-labels

# Check pod node selector
kubectl get deployment/vision-api -n vision-app -o yaml | grep nodeSelector

# Solution: Add label to node or remove node selector
kubectl label nodes <node-name> workload=ml
```

---

### Pods in CrashLoopBackOff

**Symptoms**:
- Pods restart repeatedly
- Status shows `CrashLoopBackOff`

**Diagnosis**:
```bash
# Check logs from crashed container
kubectl logs <pod-name> -n vision-app --previous

# Check restart count
kubectl get pods -n vision-app

# Common patterns:
# - Python import errors
# - Connection refused (Redis/MinIO)
# - Out of memory
```

**Common Causes & Solutions**:

#### 1. Missing Dependencies

```bash
# Check logs for import errors
kubectl logs <pod-name> -n vision-app --previous | grep "ModuleNotFoundError"

# Solution: Rebuild image with correct requirements.txt
docker build -t vision-api:fix -f docker/Dockerfile .
minikube image load vision-api:fix  # For Minikube
```

#### 2. Cannot Connect to Redis/MinIO

```bash
# Test Redis connectivity
kubectl run -it --rm redis-test --image=redis:alpine --restart=Never -- \
  redis-cli -h redis-master.vision-infra.svc.cluster.local ping

# Test MinIO connectivity
kubectl run -it --rm minio-test --image=minio/mc --restart=Never -- \
  mc alias set minio http://minio.vision-infra.svc.cluster.local:9000 \
  minioadmin minioadmin

# Solution: Verify services are running
kubectl get pods -n vision-infra
kubectl get svc -n vision-infra

# Check DNS resolution
kubectl run -it --rm busybox --image=busybox --restart=Never -- \
  nslookup redis-master.vision-infra.svc.cluster.local
```

#### 3. Out of Memory

```bash
# Check memory usage
kubectl top pod <pod-name> -n vision-app

# Check memory limits
kubectl describe pod <pod-name> -n vision-app | grep -A 5 "Limits"

# Solution: Increase memory limit
# Edit charts/api/values-*.yaml
resources:
  limits:
    memory: "8Gi"  # Increase from 4Gi

helm upgrade vision-api charts/api -n vision-app
```

#### 4. Missing Environment Variables

```bash
# Check environment variables in pod
kubectl exec <pod-name> -n vision-app -- env

# Check secrets exist
kubectl get secrets -n vision-infra
kubectl get secrets -n vision-app

# Solution: Create missing secrets
kubectl create secret generic minio-credentials \
  --from-literal=access-key=minioadmin \
  --from-literal=secret-key=minioadmin \
  -n vision-infra
```

---

### Pods in ImagePullBackOff

**Symptoms**:
- Pods cannot pull Docker image
- Status shows `ImagePullBackOff` or `ErrImagePull`

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n vision-app

# Look for:
# - "Failed to pull image"
# - "manifest unknown"
# - "unauthorized"
```

**Solutions**:

#### 1. Image Doesn't Exist

```bash
# Verify image exists
docker pull astitvaveergarg/vision-api:latest

# For Minikube: Load image manually
minikube image load astitvaveergarg/vision-api:latest

# Verify image in Minikube
minikube image ls | grep vision-api
```

#### 2. Image Tag Wrong

```bash
# Check deployment image
kubectl get deployment/vision-api -n vision-app -o yaml | grep image:

# Update to correct tag
kubectl set image deployment/vision-api \
  vision-api=astitvaveergarg/vision-api:latest \
  -n vision-app
```

#### 3. Rate Limited by Docker Hub

```bash
# Check rate limit headers
docker pull astitvaveergarg/vision-api:latest

# Solution: Use image pull secret (authenticated)
kubectl create secret docker-registry dockerhub \
  --docker-username=your-username \
  --docker-password=your-token \
  -n vision-app

# Add to deployment
kubectl patch serviceaccount default \
  -n vision-app \
  -p '{"imagePullSecrets": [{"name": "dockerhub"}]}'
```

---

### Pods in Error or Unknown State

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n vision-app -o wide

# Check node status
kubectl get nodes

# Check pod events
kubectl get events -n vision-app --field-selector involvedObject.name=<pod-name>
```

**Solutions**:

#### 1. Node Failed

```bash
# Check node status
kubectl get nodes

# Cordon node (prevent new pods)
kubectl cordon <node-name>

# Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Delete pod to reschedule
kubectl delete pod <pod-name> -n vision-app
```

#### 2. Restart Pod

```bash
# Delete pod (Deployment will recreate it)
kubectl delete pod <pod-name> -n vision-app

# Force delete (if stuck)
kubectl delete pod <pod-name> -n vision-app --force --grace-period=0
```

---

## Networking Issues

### Cannot Access API

**Symptoms**:
- `curl http://localhost:8000/health` times out or fails
- Frontend cannot reach backend

**Diagnosis**:
```bash
# Check service exists
kubectl get svc -n vision-app

# Check endpoints (pods behind service)
kubectl get endpoints -n vision-app

# Check pod IPs
kubectl get pods -n vision-app -o wide
```

**Solutions**:

#### 1. Service Not Created

```bash
# Verify service
kubectl get svc vision-api -n vision-app

# If missing, apply manifest
kubectl apply -f charts/api/templates/service.yaml
```

#### 2. No Endpoints (No Pods Ready)

```bash
# Check pod readiness
kubectl get pods -n vision-app

# If not ready, check readiness probe
kubectl describe pod <pod-name> -n vision-app | grep -A 10 "Readiness"

# Test readiness probe manually
kubectl exec <pod-name> -n vision-app -- curl http://localhost:8000/ready
```

#### 3. Port-Forward Not Working

```bash
# Kill existing port-forwards
pkill -f "port-forward"

# Create new port-forward
kubectl port-forward -n vision-app svc/vision-api 8000:8000

# Test
curl http://localhost:8000/health
```

#### 4. Network Policy Blocking

```bash
# Check network policies
kubectl get networkpolicies -n vision-app

# Temporarily delete to test
kubectl delete networkpolicy <policy-name> -n vision-app

# If that fixes it, update policy to allow traffic
```

---

### DNS Resolution Failures

**Symptoms**:
- Pods cannot resolve service names
- `nslookup redis-master.vision-infra.svc.cluster.local` fails

**Diagnosis**:
```bash
# Test DNS from pod
kubectl run -it --rm busybox --image=busybox --restart=Never -- \
  nslookup redis-master.vision-infra.svc.cluster.local

# Check DNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Solutions**:

#### 1. CoreDNS Not Running

```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```

#### 2. Wrong Service Name

```bash
# List all services
kubectl get svc -A

# Use fully qualified name
# Format: <service>.<namespace>.svc.cluster.local
redis-master.vision-infra.svc.cluster.local
```

---

### Cannot Access from Outside

**Symptoms**:
- Cannot access API from browser/curl on host machine
- Minikube service not accessible

**Solutions**:

#### 1. NodePort Not Exposed

```bash
# Get NodePort URL
minikube service vision-api -n vision-app --url

# Access via NodePort
curl http://192.168.49.2:30080/health
```

#### 2. LoadBalancer Pending (Cloud)

```bash
# Check service
kubectl get svc vision-api -n vision-app

# If EXTERNAL-IP shows <pending>:
# - AWS: Install ALB controller
# - Azure: Wait 2-3 minutes for provisioning
# - Minikube: Use NodePort instead
```

#### 3. Firewall/Security Group Blocking

```bash
# AWS: Check security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Azure: Check NSG rules
az network nsg rule list --resource-group <rg> --nsg-name <nsg>

# Add rule to allow HTTP/HTTPS
```

---

## Storage Issues

### PVC Not Binding

**Symptoms**:
- PersistentVolumeClaim stuck in `Pending`
- Pods waiting for volume

**Diagnosis**:
```bash
# Check PVC status
kubectl get pvc -n vision-infra

# Check PV availability
kubectl get pv

# Check storage class
kubectl get storageclass
```

**Solutions**:

#### 1. No Storage Class

```bash
# For Minikube
minikube addons enable storage-provisioner

# Verify
kubectl get storageclass

# If still missing, create one
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: k8s.io/minikube-hostpath
EOF
```

#### 2. Insufficient Disk Space

```bash
# Check node disk usage
kubectl get nodes -o custom-columns=NAME:.metadata.name,DISK:.status.capacity.ephemeral-storage

# Minikube: Increase disk size
minikube delete
minikube start --disk-size=80g
```

#### 3. Dynamic Provisioning Disabled

```bash
# Check if PV can be created
kubectl describe pvc <pvc-name> -n vision-infra

# For cloud: Verify CSI driver installed
# AWS: EBS CSI driver
# Azure: Azure Disk CSI driver
kubectl get pods -n kube-system | grep csi
```

---

### MinIO Connection Errors

**Symptoms**:
- API logs show "MinIO connection failed"
- Images not being stored

**Diagnosis**:
```bash
# Check MinIO pods
kubectl get pods -n vision-infra -l app=minio

# Check MinIO logs
kubectl logs deployment/minio -n vision-infra

# Test MinIO access
kubectl port-forward -n vision-infra svc/minio 9000:9000
# Open: http://localhost:9000 (minioadmin/minioadmin)
```

**Solutions**:

#### 1. MinIO Not Running

```bash
# Restart MinIO
kubectl rollout restart deployment/minio -n vision-infra

# Check for errors
kubectl describe deployment/minio -n vision-infra
```

#### 2. Wrong Credentials

```bash
# Check secret
kubectl get secret minio-credentials -n vision-infra -o yaml

# Decode
kubectl get secret minio-credentials -n vision-infra \
  -o jsonpath='{.data.access-key}' | base64 -d

# Update if wrong
kubectl delete secret minio-credentials -n vision-infra
kubectl create secret generic minio-credentials \
  --from-literal=access-key=minioadmin \
  --from-literal=secret-key=minioadmin \
  -n vision-infra
```

#### 3. Buckets Not Created

```bash
# Exec into MinIO pod
kubectl exec -it deployment/minio -n vision-infra -- /bin/bash

# Create buckets
mc alias set minio http://localhost:9000 minioadmin minioadmin
mc mb minio/vision-uploads
mc mb minio/vision-results
```

---

## Performance Issues

### High Latency

**Symptoms**:
- API responses slow (>2 seconds)
- Detection takes too long

**Diagnosis**:
```bash
# Check metrics
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80
# Open: http://localhost:3000
# Dashboard: "Vision API Performance"

# Check pod resource usage
kubectl top pods -n vision-app

# Check HPA scaling
kubectl get hpa -n vision-app
```

**Solutions**:

#### 1. CPU Throttling

```bash
# Check CPU limits
kubectl describe pod <pod-name> -n vision-app | grep -A 5 "Limits"

# Increase CPU limits
# Edit charts/api/values-*.yaml
resources:
  limits:
    cpu: "4000m"  # Increase from 2000m

helm upgrade vision-api charts/api -n vision-app
```

#### 2. Not Enough Replicas

```bash
# Check current replicas
kubectl get deployment/vision-api -n vision-app

# Scale manually
kubectl scale deployment/vision-api -n vision-app --replicas=5

# Or adjust HPA
kubectl edit hpa vision-api -n vision-app
# Increase maxReplicas
```

#### 3. Redis Cache Not Working

```bash
# Check Redis connection
kubectl exec -n vision-app deployment/vision-api -- \
  python -c "import redis; r=redis.Redis(host='redis-master.vision-infra'); print(r.ping())"

# Check cache hit ratio in metrics
curl http://localhost:8000/metrics | grep cache

# Low hit ratio? Check TTL settings
```

#### 4. Model Loading Slow

```bash
# Check logs for model loading time
kubectl logs deployment/vision-api -n vision-app | grep "Model loaded"

# Solution: Bake models into image (faster startup)
# Or use persistent volume for model cache
```

---

### Out of Memory

**Symptoms**:
- Pods killed with OOMKilled
- API becomes unresponsive

**Diagnosis**:
```bash
# Check memory usage
kubectl top pods -n vision-app

# Check events for OOMKilled
kubectl get events -n vision-app | grep OOMKilled

# Check memory limits
kubectl describe pod <pod-name> -n vision-app | grep -A 5 "Limits"
```

**Solutions**:

#### 1. Increase Memory Limits

```bash
# Edit values file
# charts/api/values-prod.yaml
resources:
  limits:
    memory: "8Gi"  # Increase from 4Gi

helm upgrade vision-api charts/api -n vision-app
```

#### 2. Reduce Model Cache Size

```python
# In api/services/detector.py
# Reduce cache_size from 2 to 1
model_manager = ModelManager(cache_size=1)
```

#### 3. Use Smaller Models

```bash
# Change default model to nano
# In API, set default model to yolov8n instead of yolov8x
```

---

### HPA Not Scaling

**Symptoms**:
- High CPU usage but pods not scaling
- HPA shows `<unknown>` for metrics

**Diagnosis**:
```bash
# Check HPA status
kubectl get hpa -n vision-app

# Check metrics server
kubectl top nodes
kubectl top pods -n vision-app

# If metrics show <unknown>, metrics-server not running
kubectl get pods -n kube-system | grep metrics-server
```

**Solutions**:

#### 1. Metrics Server Not Installed

```bash
# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For Minikube
minikube addons enable metrics-server

# Wait 2 minutes, then check
kubectl top nodes
```

#### 2. HPA Misconfigured

```bash
# Check HPA config
kubectl describe hpa vision-api -n vision-app

# Verify target CPU %
# Should match resource requests:
# targetCPUUtilizationPercentage: 70
# requests.cpu: 500m

# If mismatch, update HPA
kubectl edit hpa vision-api -n vision-app
```

#### 3. Scale-Up Too Slow

```bash
# Adjust HPA behavior
kubectl edit hpa vision-api -n vision-app

# Add:
behavior:
  scaleUp:
    policies:
    - type: Percent
      value: 100  # Double replicas each scale-up
      periodSeconds: 60
```

---

## Application Errors

### 500 Internal Server Error

**Diagnosis**:
```bash
# Check API logs
kubectl logs deployment/vision-api -n vision-app

# Common errors:
# - ModuleNotFoundError
# - ConnectionError (Redis/MinIO)
# - FileNotFoundError (model not found)
```

**Solutions**:

#### 1. Model Not Found

```bash
# Check model files in pod
kubectl exec deployment/vision-api -n vision-app -- ls -la models/

# Download models manually
kubectl exec deployment/vision-api -n vision-app -- \
  python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"
```

#### 2. Redis Connection Error

```bash
# Verify Redis is running
kubectl get pods -n vision-infra -l app=redis

# Test connection
kubectl exec deployment/vision-api -n vision-app -- \
  nc -zv redis-master.vision-infra 6379
```

---

### 422 Unprocessable Entity

**Cause**: Invalid request format

**Common Issues**:
- File not sent as multipart/form-data
- File field not named "file"
- Invalid model name

**Solution**:
```bash
# Correct curl format
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" \
  -F "model=yolov8n"

# NOT: -d '{"file": "..."}' (wrong!)
```

---

### Detection Results Incorrect

**Symptoms**:
- Empty detections array
- False positives/negatives
- Bounding boxes wrong

**Diagnosis**:
```bash
# Check confidence threshold
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" \
  -F "confidence=0.25"  # Lower threshold

# Check model variant
# yolov8n is fastest but least accurate
# yolov8x is slowest but most accurate
```

**Solutions**:

#### 1. Adjust Confidence Threshold

```bash
# Try different thresholds
for conf in 0.1 0.25 0.5 0.75; do
  echo "Confidence: $conf"
  curl -X POST http://localhost:8000/detect \
    -F "file=@image.jpg" \
    -F "confidence=$conf" | jq '.detection_count'
done
```

#### 2. Use Better Model

```bash
# Switch to larger model
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" \
  -F "model=yolov8x"  # Most accurate
```

---

## Infrastructure Issues

### Terraform Apply Failures

**Common Errors**:

#### 1. Backend Initialization Failed

```bash
# Error: "Failed to get existing workspaces"
# Solution: Create backend bucket first
aws s3 mb s3://vision-terraform-state

# Or update backend config
terraform init -reconfigure
```

#### 2. Insufficient Permissions

```bash
# Error: "AccessDenied"
# Solution: Check IAM permissions
aws sts get-caller-identity
# Verify user has EKS, VPC, EC2 permissions
```

#### 3. Resource Already Exists

```bash
# Error: "AlreadyExists"
# Solution: Import existing resource
terraform import aws_vpc.main vpc-12345678
```

---

### Helm Install/Upgrade Failures

**Common Errors**:

#### 1. Release Already Exists

```bash
# Error: "cannot re-use a name that is still in use"
# Solution: Delete old release
helm uninstall vision-api -n vision-app

# Or use upgrade --install
helm upgrade --install vision-api charts/api -n vision-app
```

#### 2. Values File Not Found

```bash
# Error: "values.yaml: no such file or directory"
# Solution: Use correct path
helm install vision-api charts/api \
  -n vision-app \
  -f charts/api/values-prod.yaml  # Absolute or relative to CWD
```

---

## Monitoring & Logging

### Cannot Access Grafana

**Symptoms**:
- Port-forward times out
- Grafana pod not running

**Solutions**:

```bash
# Check Grafana pod
kubectl get pods -n vision-monitoring -l app.kubernetes.io/name=grafana

# Restart if needed
kubectl rollout restart deployment/prometheus-grafana -n vision-monitoring

# Port-forward
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Default login: admin / prom-operator
```

---

### Metrics Not Appearing

**Diagnosis**:
```bash
# Check Prometheus targets
kubectl port-forward -n vision-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/targets

# Check if vision-api is listed and "UP"
```

**Solutions**:

#### 1. ServiceMonitor Not Created

```bash
# Verify ServiceMonitor
kubectl get servicemonitor -n vision-app

# If missing, create it
kubectl apply -f charts/api/templates/servicemonitor.yaml
```

#### 2. Metrics Endpoint Not Working

```bash
# Test metrics endpoint
kubectl exec deployment/vision-api -n vision-app -- \
  curl http://localhost:8000/metrics

# Should return Prometheus format metrics
```

---

## Emergency Procedures

### Complete System Failure

**Steps**:

1. **Check Cluster Status**:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Restart All Applications**:
   ```bash
   kubectl rollout restart deployment -n vision-app
   kubectl rollout restart deployment -n vision-infra
   ```

3. **Restore from Backup** (if needed):
   ```bash
   kubectl apply -f backup-vision-app.yaml
   kubectl apply -f backup-vision-infra.yaml
   ```

4. **Notify Users**:
   - Post status update
   - Estimate ETA for resolution

---

### Data Loss Prevention

**Before Destructive Operations**:

```bash
# Backup all resources
kubectl get all -n vision-app -o yaml > backup-$(date +%Y%m%d).yaml

# Backup persistent data
kubectl exec deployment/minio -n vision-infra -- \
  mc mirror minio/vision-uploads /backup/uploads

# Backup Redis data
kubectl exec deployment/redis-master -n vision-infra -- \
  redis-cli --rdb /backup/dump.rdb
```

---

### Rollback to Last Known Good State

```bash
# Application rollback
kubectl rollout undo deployment/vision-api -n vision-app

# Full stack rollback
git checkout <last-good-commit>
helmfile -e prod sync

# Infrastructure rollback
cd terraform/aws
git checkout <last-good-commit> terraform/
terraform apply -var-file=environments/prod.tfvars
```

---

## Getting Help

### Information to Gather

When reporting issues, provide:

1. **Environment**: local/dev/prod
2. **Kubernetes version**: `kubectl version`
3. **Helm version**: `helm version`
4. **Pod status**: `kubectl get pods -A`
5. **Events**: `kubectl get events -A --sort-by='.lastTimestamp' | tail -20`
6. **Logs**: `kubectl logs <pod-name> -n vision-app`
7. **Describe output**: `kubectl describe pod <pod-name> -n vision-app`

### Support Channels

- **GitHub Issues**: [Vision-AI Issues](https://github.com/astitvaveergarg/Vision-AI/issues)
- **Discussions**: [GitHub Discussions](https://github.com/astitvaveergarg/Vision-AI/discussions)
- **Email**: [Support email if configured]

---

## Preventive Maintenance

### Regular Health Checks

```bash
# Weekly checks
kubectl get pods -A  # No CrashLoopBackOff
kubectl top nodes     # CPU < 80%, Memory < 85%
kubectl get pvc -A    # Disk usage < 80%

# Monthly checks
helm list -A          # All releases healthy
kubectl get nodes     # No NotReady nodes
```

### Monitoring Alerts

Set up alerts for:
- Pod restarts > 3 in 10 minutes
- CPU usage > 90% for 5 minutes
- Memory usage > 85% for 5 minutes
- Disk usage > 80%
- API error rate > 5%
- High latency (p95 > 2s)

---

**Last Updated**: February 13, 2026  
**Author**: Astitva Veer Garg
