# Pre-Testing Checklist

Before deploying to cloud clusters, complete these prerequisite tasks:

## 🔐 1. Secrets Management

### AWS EKS

```bash
# Create secrets in all namespaces
kubectl create namespace vision-infra
kubectl create namespace vision-app

# MinIO credentials
kubectl create secret generic minio-credentials \
  --from-literal=access-key=YOUR_ACCESS_KEY \
  --from-literal=secret-key=YOUR_SECRET_KEY \
  -n vision-infra

# Redis credentials
kubectl create secret generic redis-credentials \
  --from-literal=password=YOUR_REDIS_PASSWORD \
  -n vision-infra

# CDN origin validation secret (prod only)
CDN_SECRET=$(aws secretsmanager get-secret-value --secret-id vision-prod-cdn-secret --query SecretString --output text)
kubectl create secret generic cdn-secret \
  --from-literal=CDN_SECRET=$CDN_SECRET \
  -n vision-app
```

### Azure AKS

```bash
# Create secrets in all namespaces
kubectl create namespace vision-infra
kubectl create namespace vision-app

# MinIO credentials
kubectl create secret generic minio-credentials \
  --from-literal=access-key=YOUR_ACCESS_KEY \
  --from-literal=secret-key=YOUR_SECRET_KEY \
  -n vision-infra

# Redis credentials
kubectl create secret generic redis-credentials \
  --from-literal=password=YOUR_REDIS_PASSWORD \
  -n vision-infra

# Alternative: Use Azure Key Vault integration
# See terraform-aks README for Key Vault setup
```

## 🌐 2. VPN/Bastion Access Setup

Since clusters are private, you need network access:

### Option A: VPN (Recommended for Dev Team)

**AWS Client VPN:**
```bash
# Create VPN endpoint in terraform or manually
# Add to terraform/aws/vpn.tf

resource "aws_ec2_client_vpn_endpoint" "dev" {
  description            = "VisionOps Dev VPN"
  server_certificate_arn = aws_acm_certificate.vpn_server.arn
  client_cidr_block      = "10.10.0.0/16"
  
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_client.arn
  }
  
  connection_log_options {
    enabled = false
  }
}
```

**Azure VPN Gateway:**
```bash
# Add to terraform/azure/vpn.tf

resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "${var.cluster_name}-vpn"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  
  type     = "Vpn"
  vpn_type = "RouteBased"
  
  sku = "VpnGw1"
  
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}
```

### Option B: Bastion Host (Quick Setup)

**AWS:**
```bash
# Launch EC2 instance in public subnet
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.micro \
  --key-name your-key \
  --subnet-id <public-subnet-id> \
  --security-group-ids <bastion-sg-id> \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vision-bastion}]'

# SSH into bastion, then use kubectl from there
```

**Azure:**
```bash
# Deploy Azure Bastion
az network bastion create \
  --name vision-bastion \
  --public-ip-address vision-bastion-ip \
  --resource-group vision-dev-rg \
  --vnet-name vision-dev-aks-vnet \
  --location eastus
```

## 📊 3. Monitoring Configuration

### Grafana Dashboards

```bash
# After helmfile deploy, import dashboards
kubectl port-forward -n vision-monitoring svc/prometheus-grafana 3000:80

# Login to Grafana (admin/prom-operator)
# Import these dashboards:
# - Kubernetes Cluster Monitoring (ID: 7249)
# - Kubernetes Deployment Metrics (ID: 8588)
# - NGINX Ingress Controller (ID: 9614)
# - Redis Dashboard (ID: 11835)
```

### AlertManager Rules

Create `charts/monitoring/prometheus/alert-rules.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: alerting-rules
  namespace: vision-monitoring
data:
  vision-alerts.yaml: |
    groups:
    - name: vision-api
      interval: 30s
      rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} requests/sec"
      
      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m])) > 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High inference latency"
          description: "P95 latency is {{ $value }}s"
      
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod is crash looping"
          description: "Pod {{ $labels.pod }} has restarted {{ $value }} times"
```

## 🔧 4. Update Terraform Variables

### AWS (terraform/aws/environments/dev.tfvars)

```hcl
# Update with your actual subscription
# Already set, but verify:
aws_region = "us-east-1"
```

### Azure (terraform/azure/environments/dev.tfvars)

```hcl
# REQUIRED: Replace with your subscription ID
subscription_id = "00000000-0000-0000-0000-000000000000" # ← CHANGE THIS

# Get your subscription ID:
# az account list --output table
# az account show --query id -o tsv
```

## 🚀 5. Domain Configuration (Production Only)

### AWS Route 53

```bash
# Create hosted zone
aws route53 create-hosted-zone \
  --name vision.yourdomain.com \
  --caller-reference $(date +%s)

# Get CloudFront domain
CLOUDFRONT_DOMAIN=$(cd terraform/aws && terraform output -raw cloudfront_domain_name)

# Create CNAME record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.yourdomain.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$CLOUDFRONT_DOMAIN'"}]
      }
    }]
  }'
```

### Azure DNS

```bash
# Create DNS zone
az network dns zone create \
  --resource-group vision-prod-rg \
  --name vision.yourdomain.com

# Get Front Door domain
FRONTDOOR_DOMAIN=$(cd terraform/azure && terraform output -raw frontdoor_endpoint_hostname)

# Create CNAME record
az network dns record-set cname create \
  --resource-group vision-prod-rg \
  --zone-name vision.yourdomain.com \
  --name api

az network dns record-set cname set-record \
  --resource-group vision-prod-rg \
  --zone-name vision.yourdomain.com \
  --record-set-name api \
  --cname $FRONTDOOR_DOMAIN
```

## ✅ Checklist Summary

Before testing, complete:

- [ ] Create Kubernetes secrets for MinIO, Redis, CDN
- [ ] Setup VPN or Bastion for private cluster access
- [ ] Verify Terraform variables (especially Azure subscription ID)
- [ ] Import Grafana dashboards
- [ ] Configure AlertManager rules
- [ ] (Prod only) Configure custom domain DNS records

## 🧪 Ready to Test?

Once above items are complete, you can proceed with:

1. **Local Testing**: Works now via docker-compose
2. **Dev Cluster Testing**: Deploy via `helmfile -e dev apply` after VPN setup
3. **Prod Cluster Testing**: Full deployment with CDN after all prerequisites

---

**Estimated Time**: 2-4 hours for complete setup (VPN is the longest part)
