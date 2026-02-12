# Check status of all VisionOps services

Write-Host "🔍 Checking VisionOps Services..." -ForegroundColor Cyan

Write-Host "`n📦 Infrastructure Services (vision-infra):" -ForegroundColor Yellow
kubectl get pods -n vision-infra

Write-Host "`n📊 Monitoring Services (vision-monitoring):" -ForegroundColor Yellow
kubectl get pods -n vision-monitoring

Write-Host "`n🌐 Application Services (vision-app):" -ForegroundColor Yellow
kubectl get pods -n vision-app

Write-Host "`n🔗 NodePort Services:" -ForegroundColor Magenta
kubectl get svc -n vision-infra -o wide | Select-String "NodePort"
kubectl get svc -n vision-monitoring -o wide | Select-String "NodePort"

Write-Host "`n💾 Persistent Volumes:" -ForegroundColor Yellow
kubectl get pvc -A

Write-Host "`n📈 Resource Usage:" -ForegroundColor Cyan
kubectl top nodes
Write-Host ""
kubectl top pods -A --sort-by=memory | Select-Object -First 10
