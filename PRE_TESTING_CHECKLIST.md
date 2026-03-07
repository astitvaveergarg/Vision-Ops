# VisionOps — Pre-Testing Checklist

This checklist must be completed before running any Kubernetes deployment.

---

## 1. GKE (Active — Start Here)

### Status: ✅ Cluster `vision-dev-gke` is provisioned in `us-central1-a`

#### a. Prerequisites

- [ ] `gcloud` CLI installed and authenticated: `gcloud auth login`
- [ ] kubectl configured: `gcloud container clusters get-credentials vision-dev-gke --zone us-central1-a --project <project-id>`
- [ ] Verify: `kubectl get nodes` returns 2 nodes

#### b. Namespaces

```bash
kubectl create namespace vision-infra      --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vision-app        --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vision-monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ingress-nginx     --dry-run=client -o yaml | kubectl apply -f -
```

#### c. Kubernetes Secrets (Required before helmfile sync)

> See `k8s/secrets-dev.yaml.example` for the full YAML template.

**MinIO Credentials** (needed in BOTH namespaces):

```bash
# vision-infra namespace (MinIO pod itself)
kubectl create secret generic vision-minio-credentials \
  --from-literal=rootUser=minioadmin \
  --from-literal=rootPassword=<your-minio-password> \
  -n vision-infra --dry-run=client -o yaml | kubectl apply -f -

# vision-app namespace (API reads from here)
kubectl create secret generic vision-minio-credentials \
  --from-literal=rootUser=minioadmin \
  --from-literal=rootPassword=<your-minio-password> \
  -n vision-app --dry-run=client -o yaml | kubectl apply -f -
```

**Redis Credentials** (needed in BOTH namespaces):

```bash
kubectl create secret generic vision-redis-credentials \
  --from-literal=password=<your-redis-password> \
  -n vision-infra --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic vision-redis-credentials \
  --from-literal=password=<your-redis-password> \
  -n vision-app --dry-run=client -o yaml | kubectl apply -f -
```

**Grafana Credentials**:

```bash
kubectl create secret generic vision-grafana-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<your-grafana-password> \
  -n vision-monitoring --dry-run=client -o yaml | kubectl apply -f -
```

> Using `--dry-run=client -o yaml | kubectl apply -f -` is idempotent — safe to re-run.

#### d. Verify Secrets

```bash
kubectl get secrets -n vision-infra
kubectl get secrets -n vision-app
kubectl get secrets -n vision-monitoring
```

Expected secrets:
- `vision-infra`: `vision-minio-credentials`, `vision-redis-credentials`
- `vision-app`: `vision-minio-credentials`, `vision-redis-credentials`
- `vision-monitoring`: `vision-grafana-credentials`

#### e. Deploy

```bash
helmfile -e dev sync
kubectl get pods -A -w
```

#### f. Access Verification

```bash
# Get external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Test
curl http://<EXTERNAL_IP>/api/health
curl http://<EXTERNAL_IP>/health   # via frontend
```

---

## 2. Minikube (Local K8s)

### Status: ⏳ Not yet tested

#### Prerequisites

- [ ] Minikube installed: `minikube version`
- [ ] Minikube running: `minikube start --cpus=4 --memory=8192 --disk-size=40g`
- [ ] ingress addon: `minikube addons enable ingress`

#### Secrets (same names and keys as GKE):

```bash
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring

kubectl create secret generic vision-minio-credentials \
  --from-literal=rootUser=minioadmin \
  --from-literal=rootPassword=minioadmin123 \
  -n vision-infra

kubectl create secret generic vision-minio-credentials \
  --from-literal=rootUser=minioadmin \
  --from-literal=rootPassword=minioadmin123 \
  -n vision-app

kubectl create secret generic vision-redis-credentials \
  --from-literal=password=redis123 \
  -n vision-infra

kubectl create secret generic vision-redis-credentials \
  --from-literal=password=redis123 \
  -n vision-app

kubectl create secret generic vision-grafana-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=admin123 \
  -n vision-monitoring
```

#### Deploy:

```bash
helmfile -e local sync
minikube service ingress-nginx-controller -n ingress-nginx --url
```

---

## 3. AWS EKS

### Status: ⏳ IaC complete, cluster not yet provisioned

#### Prerequisites

- [ ] `aws` CLI configured: `aws configure`  
- [ ] Terraform state S3 bucket created (see `terraform/aws/README.md`)
- [ ] Terraform applied: `cd terraform/aws && terraform apply -var-file=environments/dev.tfvars`
- [ ] VPN or bastion configured (private cluster)
- [ ] kubectl configured: `aws eks update-kubeconfig --region us-east-1 --name vision-dev`

#### Secrets (same names and pattern):

Use same `kubectl create secret` commands as GKE section above, targeting same namespaces.

> See `k8s/secrets-dev.yaml.example` for YAML-manifest approach.

---

## 4. Azure AKS

### Status: ⏳ IaC complete, cluster not yet provisioned

#### Prerequisites

- [ ] `az` CLI configured: `az login`  
- [ ] `subscription_id` updated in `terraform/azure/environments/dev.tfvars`
- [ ] Terraform state storage account created (see `terraform/azure/README.md`)
- [ ] Terraform applied
- [ ] kubectl configured: `az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks`

#### Secrets: Same as GKE section above.

---

## 5. Secret Name Reference

| Secret Name | Keys | Namespace(s) |
|-------------|------|------|
| `vision-minio-credentials` | `rootUser`, `rootPassword` | `vision-infra`, `vision-app` |
| `vision-redis-credentials` | `password` | `vision-infra`, `vision-app` |
| `vision-grafana-credentials` | `admin-user`, `admin-password` | `vision-monitoring` |

> **Both cross-namespace copies are mandatory.** MinIO/Redis pods read from `vision-infra`, the API pod reads from `vision-app`.

---

## 6. Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck in `CreateContainerConfigError` | Secret not found | Check secret exists in correct namespace |
| MinIO `CrashLoopBackOff` | Wrong secret key names | Must be `rootUser`/`rootPassword` (not `access-key`) |
| API `401` on MinIO | Different passwords in two namespace copies | Recreate both with same value |
| Swagger UI "parser error" | `ROOT_PATH` not set | Ensure `env.ROOT_PATH=/api` in `charts/api/values.yaml` |
| PVC stuck `Pending` | Storage class unresolvable | GKE uses `standard`, EKS uses `gp3`, AKS uses `managed` |

---

## 7. Validation Commands

```bash
# All pods healthy
kubectl get pods -A

# Secrets present
kubectl get secrets -n vision-infra
kubectl get secrets -n vision-app

# API responding
curl http://<ingress-ip>/api/health

# Redis reachable (from API pod)
kubectl exec -n vision-app deploy/vision-api -- \
  python -c "import redis; r=redis.Redis(host='vision-redis-master.vision-infra',password='<pw>'); print(r.ping())"

# Logs
kubectl logs -f deploy/vision-api -n vision-app
```
