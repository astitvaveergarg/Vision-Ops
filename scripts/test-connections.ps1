# Test connectivity to Minikube services

Write-Host "🧪 Testing VisionOps Service Connectivity..." -ForegroundColor Cyan

# Test Redis
Write-Host "`n📍 Testing Redis (localhost:30379)..." -ForegroundColor Yellow
try {
    $redis = New-Object System.Net.Sockets.TcpClient
    $redis.Connect("localhost", 30379)
    if ($redis.Connected) {
        Write-Host "   ✅ Redis is accessible" -ForegroundColor Green
        $redis.Close()
    }
} catch {
    Write-Host "   ❌ Redis is not accessible" -ForegroundColor Red
}

# Test MinIO
Write-Host "`n📍 Testing MinIO (localhost:30900)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:30900/minio/health/live" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ MinIO is accessible" -ForegroundColor Green
} catch {
    Write-Host "   ❌ MinIO is not accessible" -ForegroundColor Red
}

# Test Grafana
Write-Host "`n📍 Testing Grafana (localhost:30300)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:30300/api/health" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ Grafana is accessible" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Grafana is not accessible" -ForegroundColor Red
}

Write-Host "`n💡 If services are not accessible:" -ForegroundColor Magenta
Write-Host "   1. Check pods: kubectl get pods -n vision-infra"
Write-Host "   2. Check services: kubectl get svc -n vision-infra"
Write-Host "   3. Port forward manually: kubectl port-forward svc/redis-master 30379:6379 -n vision-infra"
