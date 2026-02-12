# VisionOps - Quick Start Guide

Get VisionOps up and running in 10 minutes with GitHub Actions + GHCR + Kubernetes.

---

## Prerequisites

- GitHub account
- Git installed
- Docker installed
- kubectl configured
- Minikube or Kubernetes cluster access

---

## Step 1: Initialize GitHub Repository

```bash
# Navigate to project directory
cd D:\Development\Vision\vision

# Update repository references (replace YOUR_USERNAME)
$username = "YOUR_GITHUB_USERNAME"
Get-ChildItem -Recurse -Include *.yaml | ForEach-Object {
    (Get-Content $_) -replace 'YOUR_USERNAME', $username | Set-Content $_
}

# Initialize git (if not already)
git init
git add .
git commit -m "Initial commit: VisionOps with CI/CD"

# Create GitHub repository and push
gh repo create vision --public --source=. --remote=origin --push

# Or manually:
# 1. Create repo on GitHub: https://github.com/new
# 2. git remote add origin https://github.com/$username/vision.git
# 3. git push -u origin main
```

---

## Step 2: Configure Secrets

```bash
# Generate base64-encoded kubeconfig
$kubeconfig = Get-Content ~/.kube/config -Raw
$bytes = [System.Text.Encoding]::UTF8.GetBytes($kubeconfig)
$encoded = [Convert]::ToBase64String($bytes)
Write-Output $encoded

# Add to GitHub Secrets:
# https://github.com/YOUR_USERNAME/vision/settings/secrets/actions

# Required secrets:
# - KUBE_CONFIG_DEV: (paste encoded kubeconfig above)
# - KUBE_CONFIG_STAGING: (for staging cluster)
# - KUBE_CONFIG_PROD: (for production cluster)
```

---

## Step 3: Test CI Pipeline

```bash
# Create test branch
git checkout -b test/ci-pipeline

# Make small change
echo "# CI/CD Test" >> README.md
git add README.md
git commit -m "test: trigger CI pipeline"
git push origin test/ci-pipeline

# Watch GitHub Actions
# https://github.com/YOUR_USERNAME/vision/actions

# Expected workflow:
# 1. ✅ Lint and test
# 2. ✅ Build Docker image
# 3. ✅ Push to GHCR (ghcr.io/YOUR_USERNAME/vision:test-ci-pipeline-SHA)
# 4. ✅ Security scan
```

---

## Step 4: Verify Image in GHCR

```bash
# View your images
# https://github.com/YOUR_USERNAME?tab=packages

# Pull image locally
docker login ghcr.io -u YOUR_USERNAME
docker pull ghcr.io/YOUR_USERNAME/vision:latest

# Test locally
docker run -p 8000:8000 \
  -e REDIS_HOST=localhost \
  -e MINIO_HOST=localhost \
  ghcr.io/YOUR_USERNAME/vision:latest

# Verify API
curl http://localhost:8000/health
```

---

## Step 5: Deploy to Development

### Option A: Automatic (after merging to main)

```bash
# Merge your test PR
gh pr create --title "test: CI pipeline" --body "Testing CI/CD"
gh pr merge --auto --squash

# CI/CD automatically:
# 1. Runs CI workflow
# 2. Triggers CD workflow
# 3. Deploys to dev environment
```

### Option B: Manual Deployment

```bash
# Via GitHub UI
1. Go to: https://github.com/YOUR_USERNAME/vision/actions/workflows/cd.yaml
2. Click "Run workflow"
3. Select: environment = "dev", image_tag = "latest"
4. Click "Run workflow"

# Via GitHub CLI
gh workflow run cd.yaml \
  -f environment=dev \
  -f image_tag=latest

# Monitor deployment
watch kubectl get pods -n vision-app
```

### Option C: Direct Helm Deployment (Local)

```bash
# Start Minikube with infrastructure
.\scripts\start-minikube.ps1
.\scripts\deploy-infrastructure.ps1

# Load image into Minikube
minikube image load ghcr.io/YOUR_USERNAME/vision:latest

# Deploy with Helm
helm upgrade --install vision-api ./charts/api \
  --values ./charts/api/values-local.yaml \
  --set image.repository=ghcr.io/YOUR_USERNAME/vision \
  --set image.tag=latest \
  --namespace vision-app \
  --create-namespace \
  --wait

# Verify
kubectl get pods -n vision-app
kubectl logs -f deployment/vision-api -n vision-app

# Port forward
kubectl port-forward svc/vision-api 8000:8000 -n vision-app

# Test API
curl http://localhost:8000/health
curl -X POST http://localhost:8000/detect -F "file=@test-bus.jpg"
```

---

## Step 6: Create First Release

```bash
# Ensure main branch is up-to-date
git checkout main
git pull origin main

# Create semantic version tag
git tag -a v1.0.0 -m "Release v1.0.0: Initial production release"
git push origin v1.0.0

# This automatically:
# 1. Triggers release workflow
# 2. Builds multi-platform image (amd64 + arm64)
# 3. Tags: v1.0.0, v1.0, v1, stable, latest
# 4. Generates SBOM
# 5. Runs security scan
# 6. Creates GitHub Release

# View release
# https://github.com/YOUR_USERNAME/vision/releases/tag/v1.0.0
```

---

## Step 7: Deploy to Production

```bash
# Setup environment approval (one-time)
# 1. Go to: https://github.com/YOUR_USERNAME/vision/settings/environments
# 2. Click "production"
# 3. Enable "Required reviewers" and add yourself
# 4. Save protection rules

# Trigger production deployment
gh workflow run cd.yaml \
  -f environment=prod \
  -f image_tag=v1.0.0

# Approve deployment
# 1. Go to: https://github.com/YOUR_USERNAME/vision/actions
# 2. Click on the running workflow
# 3. Click "Review deployments"
# 4. Select "production" and click "Approve and deploy"

# Monitor blue-green deployment
kubectl get pods -n vision-app -w
kubectl get svc vision-api -n vision-app

# Verify traffic switch
kubectl describe svc vision-api -n vision-app | grep Selector
```

---

## Verification Checklist

After deployment, verify everything works:

```bash
# ✅ Pods running
kubectl get pods -n vision-app

# ✅ Health check
curl http://$(kubectl get svc vision-api -n vision-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/health

# ✅ Models endpoint
curl http://$(kubectl get svc vision-api -n vision-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/models

# ✅ Detection works
curl -X POST \
  http://$(kubectl get svc vision-api -n vision-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/detect \
  -F "file=@test-bus.jpg"

# ✅ Metrics exposed
curl http://$(kubectl get svc vision-api -n vision-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/metrics

# ✅ HPA configured
kubectl get hpa -n vision-app

# ✅ Monitoring working
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090

# ✅ Grafana dashboards
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Open: http://localhost:3000 (admin/prom-operator)
```

---

## Common Issues & Solutions

### Issue: Image pull fails

```bash
# Solution: Make package public
# 1. Go to: https://github.com/YOUR_USERNAME?tab=packages
# 2. Click on "vision" package
# 3. Click "Package settings"
# 4. Scroll to "Danger Zone"
# 5. Click "Change visibility" → "Public"
```

### Issue: kubectl can't connect

```bash
# Verify kubeconfig
kubectl cluster-info
kubectl config current-context

# Test secret is valid
$env:KUBE_CONFIG_DEV | base64 -d | kubectl config view --flatten
```

### Issue: Helm deployment fails

```bash
# Check Helm release
helm list -n vision-app

# Debug deployment
helm upgrade vision-api ./charts/api \
  -f charts/api/values-local.yaml \
  --dry-run --debug

# View full manifest
helm get manifest vision-api -n vision-app
```

### Issue: CI tests fail

```bash
# Run tests locally
cd api
python -m pytest tests/ -v

# Fix linting issues
black .
flake8 .
```

---

## Next Steps

Now that your CI/CD pipeline is working:

1. **Customize Workflows**
   - Add more test coverage
   - Integrate with your favorite tools
   - Add deployment notifications

2. **Production Hardening**
   - Set up external secrets (AWS Secrets Manager, Vault)
   - Configure auto-scaling policies
   - Implement backup strategies
   - Set up log aggregation (ELK, Loki)

3. **Monitoring & Observability**
   - Create Grafana dashboards
   - Set up alerting rules
   - Integrate with PagerDuty/Opsgenie

4. **Documentation**
   - Document runbooks
   - Create architecture diagrams
   - Write incident response procedures

---

## Resources

- 📖 [Full CI/CD Guide](./CI_CD_GUIDE.md)
- 📖 [Deployment Plan](./DEPLOYMENT_PLAN.md)
- 📖 [Multi-Model Test Results](./MULTI_MODEL_TEST_RESULTS.md)
- 🐙 [GitHub Actions Docs](https://docs.github.com/en/actions)
- 📦 [GHCR Docs](https://docs.github.com/en/packages)
- ⎈ [Helm Docs](https://helm.sh/docs/)

---

**Congratulations!** 🎉 

You now have a **production-grade CI/CD pipeline** for your ML inference platform!

Every push triggers automated:
- ✅ Testing
- ✅ Building
- ✅ Security scanning
- ✅ Deployment (with appropriate controls)

This is the same approach used by **professional cloud-native teams** at scale.
