# Deploy infrastructure services to Minikube

param(
    [string]$Environment = "local"
)

Write-Host "🚀 Deploying VisionOps Infrastructure to $Environment..." -ForegroundColor Cyan

# Create namespaces
Write-Host "`n📦 Creating namespaces..." -ForegroundColor Yellow
kubectl create namespace vision-infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vision-monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vision-app --dry-run=client -o yaml | kubectl apply -f -

# Deploy with Helmfile
Write-Host "`n⚙️  Deploying services..." -ForegroundColor Yellow
helmfile -e $Environment apply

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Infrastructure deployed successfully" -ForegroundColor Green
    
    Write-Host "`n⏳ Waiting for pods to be ready..." -ForegroundColor Cyan
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n vision-infra --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n vision-infra --timeout=300s
    
    Write-Host "`n📊 Service Status:" -ForegroundColor Yellow
    kubectl get pods -n vision-infra
    kubectl get pods -n vision-monitoring
    
    Write-Host "`n🔗 Service Access (NodePort):" -ForegroundColor Magenta
    Write-Host "   Redis:    localhost:30379"
    Write-Host "   MinIO:    localhost:30900"
    Write-Host "   Grafana:  localhost:30300 (admin/admin)"
    
    Write-Host "`n💡 Next step:" -ForegroundColor Cyan
    Write-Host "   cd api && python main.py"
} else {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}
