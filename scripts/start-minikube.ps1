# Start Minikube with recommended settings for VisionOps

Write-Host "🚀 Starting Minikube for VisionOps..." -ForegroundColor Cyan

minikube start `
    --cpus=4 `
    --memory=8192 `
    --disk-size=20g `
    --driver=docker `
    --kubernetes-version=v1.28.3

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Minikube started successfully" -ForegroundColor Green
    
    Write-Host "`n📊 Enabling addons..." -ForegroundColor Cyan
    minikube addons enable metrics-server
    minikube addons enable ingress
    
    Write-Host "`n📦 Cluster Info:" -ForegroundColor Yellow
    kubectl cluster-info
    
    Write-Host "`n💡 Next steps:" -ForegroundColor Magenta
    Write-Host "   1. Deploy infrastructure: helmfile -e local apply"
    Write-Host "   2. Check services: kubectl get pods -A"
    Write-Host "   3. Start development: cd api && python main.py"
} else {
    Write-Host "❌ Failed to start Minikube" -ForegroundColor Red
    exit 1
}
