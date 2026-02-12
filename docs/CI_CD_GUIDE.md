# VisionOps CI/CD Pipeline

Complete automation for building, testing, and deploying VisionOps to Kubernetes using GitHub Actions and GitHub Container Registry (GHCR).

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Setup Instructions](#setup-instructions)
- [Usage Guide](#usage-guide)
- [Deployment Environments](#deployment-environments)
- [Security & Best Practices](#security--best-practices)

---

## 🏗️ Architecture Overview

```
┌─────────────┐
│  Developer  │
└──────┬──────┘
       │ git push
       ▼
┌─────────────────────────────────────────────────────┐
│                    GitHub                            │
│                                                      │
│  ┌────────────────────────────────────────────┐   │
│  │          CI Workflow (ci.yaml)             │   │
│  │  1. Lint & Test                            │   │
│  │  2. Build Docker Image                     │   │
│  │  3. Push to GHCR                           │   │
│  │  4. Security Scan (Trivy)                  │   │
│  └────────────┬───────────────────────────────┘   │
│               │  On success                        │
│               ▼                                     │
│  ┌────────────────────────────────────────────┐   │
│  │         CD Workflow (cd.yaml)              │   │
│  │  1. Deploy to Dev (auto)                   │   │
│  │  2. Deploy to Staging (manual)             │   │
│  │  3. Deploy to Prod (manual + approval)     │   │
│  └────────────┬───────────────────────────────┘   │
│               │                                     │
└───────────────┼─────────────────────────────────────┘
                │
                ▼
┌────────────────────────────────────────────────┐
│          Kubernetes Clusters                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │   Dev    │  │ Staging  │  │   Prod   │    │
│  │ Minikube │  │   EKS    │  │   EKS    │    │
│  └──────────┘  └──────────┘  └──────────┘    │
└────────────────────────────────────────────────┘
```

---

## ⚙️ GitHub Actions Workflows

### 1. CI Workflow (`ci.yaml`)

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`

**Jobs:**
1. **lint-and-test**
   - Runs flake8 for linting
   - Checks code formatting with black
   - Executes pytest with coverage
   - Uploads coverage to Codecov

2. **build-image**
   - Builds Docker image using multi-stage Dockerfile
   - Pushes to GitHub Container Registry
   - Tags: `latest`, `branch-sha`, branch name
   - Uses Docker buildx cache for faster builds

3. **security-scan**
   - Scans image with Trivy
   - Uploads results to GitHub Security tab
   - Fails on CRITICAL/HIGH vulnerabilities

### 2. CD Workflow (`cd.yaml`)

**Triggers:**
- Automatic: On successful CI workflow (main branch only)
- Manual: workflow_dispatch with environment selection

**Environments:**
- **Development**: Auto-deploy on CI success
- **Staging**: Manual trigger required
- **Production**: Manual trigger + environment approval

**Deployment Strategy:**
- **Dev/Staging**: Rolling update
- **Production**: Blue-Green deployment

### 3. Release Workflow (`release.yaml`)

**Triggers:**
- Push tags matching `v*.*.*` (e.g., `v1.0.0`)

**Features:**
- Semantic versioning (major, minor, patch)
- Multi-platform builds (amd64, arm64)
- Multiple tags: `1.0.0`, `1.0`, `1`, `stable`, `latest`
- Generates SBOM (Software Bill of Materials)
- Creates GitHub Release with notes
- Comprehensive security scanning

---

## 🚀 Setup Instructions

### 1. GitHub Repository Setup

```bash
# 1. Create GitHub repository
git remote add origin https://github.com/YOUR_USERNAME/vision.git

# 2. Update image references
find .github charts -type f -name '*.yaml' -exec sed -i 's/YOUR_USERNAME/your-github-username/g' {} +

# 3. Push code
git add .
git commit -m "feat: add CI/CD pipeline"
git push -u origin main
```

### 2. GitHub Secrets Configuration

Navigate to **Settings → Secrets and variables → Actions** and add:

#### Required Secrets

```yaml
# Kubernetes Cluster Configs (base64 encoded)
KUBE_CONFIG_DEV: <base64-encoded-kubeconfig>
KUBE_CONFIG_STAGING: <base64-encoded-kubeconfig>
KUBE_CONFIG_PROD: <base64-encoded-kubeconfig>

# MinIO Credentials
MINIO_ACCESS_KEY: minioadmin
MINIO_SECRET_KEY: minioadmin

# Optional: Slack Notifications
SLACK_WEBHOOK: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

#### Generate kubeconfig secrets:

```bash
# For each environment
cat ~/.kube/config | base64 -w 0

# Or for specific context
kubectl config view --flatten --minify --context=dev-cluster | base64 -w 0
```

### 3. GitHub Container Registry (GHCR)

GHCR is automatically configured with `GITHUB_TOKEN`. No additional setup needed!

**Image URL format:**
```
ghcr.io/YOUR_USERNAME/vision:latest
ghcr.io/YOUR_USERNAME/vision:v1.0.0
```

### 4. Environment Protection Rules

1. Go to **Settings → Environments**
2. Create environments: `development`, `staging`, `production`
3. Configure **production** environment:
   - ✅ Required reviewers: Add team members
   - ✅ Wait timer: 5 minutes (optional)
   - ✅ Deployment branches: Only `main`

---

## 📖 Usage Guide

### Standard Development Workflow

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes
# ... code changes ...

# 3. Commit and push
git add .
git commit -m "feat: add my feature"
git push origin feature/my-feature

# 4. Create Pull Request
# CI workflow runs automatically:
#   - Lints code
#   - Runs tests
#   - Builds Docker image
#   - Scans for vulnerabilities

# 5. Merge to main
# After PR approval and merge:
#   - CI workflow runs again
#   - CD workflow auto-deploys to dev environment
```

### Deploy to Staging

```bash
# Option 1: Via GitHub UI
1. Go to Actions → CD - Deploy to Kubernetes
2. Click "Run workflow"
3. Select environment: "staging"
4. Enter image tag: "latest" or specific SHA
5. Click "Run workflow"

# Option 2: Via GitHub CLI
gh workflow run cd.yaml \
  -f environment=staging \
  -f image_tag=latest
```

### Deploy to Production

```bash
# 1. Create release tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# This triggers release workflow:
#   - Builds multi-platform image
#   - Tags: v1.0.0, v1.0, v1, stable, latest
#   - Runs comprehensive security scan
#   - Generates SBOM
#   - Creates GitHub Release

# 2. Deploy to production
gh workflow run cd.yaml \
  -f environment=prod \
  -f image_tag=v1.0.0

# 3. Requires approval from designated reviewers
# 4. Blue-green deployment: deploys to "green", tests, switches traffic
```

### Hotfix Workflow

```bash
# 1. Create hotfix branch from production tag
git checkout -b hotfix/critical-fix v1.0.0

# 2. Make fix and commit
git add .
git commit -m "fix: critical security patch"

# 3. Create patch release
git tag -a v1.0.1 -m "Hotfix: critical security patch"
git push origin hotfix/critical-fix v1.0.1

# 4. Deploy hotfix
gh workflow run cd.yaml \
  -f environment=prod \
  -f image_tag=v1.0.1

# 5. Merge hotfix back to main
git checkout main
git merge hotfix/critical-fix
git push origin main
```

---

## 🌍 Deployment Environments

### Development (Minikube)

**Purpose:** Local testing, rapid iteration

```yaml
Environment: development
URL: http://dev.visionops.local
Replicas: 1
Resources: 512Mi RAM, 250m CPU
Auto-deploy: Yes (on main branch push)
Image tag: latest
```

**Deploy manually:**
```bash
helm upgrade --install vision-api ./charts/api \
  -f charts/api/values-local.yaml \
  --set image.tag=dev
```

### Staging (EKS)

**Purpose:** Pre-production testing, QA validation

```yaml
Environment: staging
URL: https://api-staging.visionops.com
Replicas: 2-8 (HPA)
Resources: 2Gi RAM, 750m CPU
Auto-deploy: No (manual trigger)
Image tag: stable or specific SHA
Ingress: Yes (TLS enabled)
Monitoring: Yes (Prometheus + Grafana)
```

**Deploy manually:**
```bash
helm upgrade --install vision-api ./charts/api \
  -f charts/api/values-staging.yaml \
  --set image.tag=stable \
  --namespace vision-app
```

### Production (EKS)

**Purpose:** Live customer-facing service

```yaml
Environment: production
URL: https://api.visionops.com
Replicas: 3-20 (HPA with conservative scaling)
Resources: 2-8Gi RAM, 1-4 CPU
Auto-deploy: No (requires approval)
Image tag: Semantic version (e.g., v1.0.0)
Ingress: Yes (TLS + rate limiting)
Monitoring: Yes (15s scrape interval)
Backup: Yes (Velero)
```

**Deploy manually:**
```bash
helm upgrade --install vision-api ./charts/api \
  -f charts/api/values-prod.yaml \
  --set image.tag=v1.0.0 \
  --namespace vision-app
```

---

## 🔒 Security & Best Practices

### Image Security

1. **Multi-stage builds**: Minimal runtime image (Python slim)
2. **Non-root user**: Runs as UID 1000
3. **Vulnerability scanning**: Trivy scans on every build
4. **SBOM generation**: Full dependency tracking
5. **Signed images**: Artifact attestation for supply chain security

### Secret Management

```bash
# NEVER commit secrets to git

# Use Kubernetes secrets for sensitive data
kubectl create secret generic minio-credentials \
  --from-literal=access-key=YOUR_KEY \
  --from-literal=secret-key=YOUR_SECRET \
  -n vision-app

# Reference in Helm values
env:
  - name: MINIO_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: minio-credentials
        key: access-key
```

### Production Checklist

- [ ] All secrets stored in Kubernetes Secrets
- [ ] TLS certificates configured (cert-manager)
- [ ] Resource limits set appropriately
- [ ] HPA configured and tested
- [ ] Pod Disruption Budget enabled (minAvailable: 2)
- [ ] Network policies applied
- [ ] Monitoring dashboards configured
- [ ] Alerting rules set up
- [ ] Backup strategy implemented (Velero)
- [ ] Disaster recovery plan documented
- [ ] Load testing completed
- [ ] Security scan passed (no HIGH/CRITICAL)
- [ ] SBOM generated and reviewed

### Rollback Procedure

```bash
# Option 1: Helm rollback
helm rollback vision-api -n vision-app

# Option 2: Deploy previous version
helm upgrade vision-api ./charts/api \
  --set image.tag=v1.0.0 \
  -n vision-app

# Option 3: Blue-green switch back
kubectl patch service vision-api -n vision-app \
  -p '{"spec":{"selector":{"version":"blue"}}}'
```

---

## 📊 Monitoring CI/CD

### GitHub Actions Dashboard

View workflow runs:
```
https://github.com/YOUR_USERNAME/vision/actions
```

### Image Registry

View published images:
```
https://github.com/YOUR_USERNAME/vision/pkgs/container/vision
```

### Deployment Status

```bash
# Check deployment status
kubectl rollout status deployment/vision-api -n vision-app

# View recent events
kubectl get events -n vision-app --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -f deployment/vision-api -n vision-app

# View metrics
kubectl top pods -n vision-app
```

---

## 🐛 Troubleshooting

### CI Workflow Fails

```bash
# Check workflow logs in GitHub Actions

# Common issues:
1. Linting errors → Run: black . && flake8 .
2. Test failures → Run: pytest tests/ -v
3. Docker build fails → Check Dockerfile syntax
4. GHCR push fails → Verify GITHUB_TOKEN permissions
```

### CD Workflow Fails

```bash
# 1. Check kubeconfig secret
echo $KUBE_CONFIG_DEV | base64 -d | kubectl config view --flatten

# 2. Verify cluster connectivity
kubectl cluster-info

# 3. Check Helm release
helm list -n vision-app
helm status vision-api -n vision-app

# 4. Debug pod issues
kubectl describe pod <pod-name> -n vision-app
kubectl logs <pod-name> -n vision-app --previous
```

### Image Pull Failures

```bash
# 1. Verify image exists
docker pull ghcr.io/YOUR_USERNAME/vision:latest

# 2. Check imagePullSecrets (if private repo)
kubectl get secret -n vision-app

# 3. Create imagePullSecret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PAT \
  -n vision-app
```

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GHCR Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Trivy Scanner](https://aquasecurity.github.io/trivy/)

---

**Last Updated:** February 13, 2026  
**Version:** 1.0.0  
**Maintainer:** VisionOps Team
