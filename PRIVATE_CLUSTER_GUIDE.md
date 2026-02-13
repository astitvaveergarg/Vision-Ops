# Private Cluster Configuration Guide

## Overview

Both EKS and AKS clusters are configured as **fully private clusters** with no public API endpoints. This provides maximum security by ensuring all access is through controlled channels.

## Architecture

### Development Environment
```
Developer Machine
    ↓ kubectl via AWS CLI / Azure CLI (authenticated)
    ↓
Private API Server (no public endpoint)
    ↓
Kubernetes Cluster (private subnets only)
    ↓
Internal Load Balancer
    ↓
Application Pods
```

**Access Method**: `kubectl port-forward`

### Production Environment
```
Internet Users
    ↓
CloudFront (AWS) / Azure Front Door (CDN)
    ↓ WAF + DDoS Protection
    ↓ Custom Header Validation
    ↓
Internal Load Balancer (private)
    ↓
Kubernetes Cluster (private subnets only)
    ↓
Application Pods
```

**Access Method**: CDN with origin validation

## Setup Instructions

### AWS EKS - Development

#### 1. Connect to Private Cluster

Since the API server has no public endpoint, you need to be in the VPC:

**Option A: VPN Connection (Recommended)**
```bash
# Setup AWS Client VPN or Site-to-Site VPN to VPC
# Then configure kubectl normally
aws eks update-kubeconfig --region us-east-1 --name vision-dev
```

**Option B: Bastion Host**
```bash
# SSH into bastion in public subnet
ssh -i key.pem ec2-user@bastion-ip

# From bastion, configure kubectl
aws eks update-kubeconfig --region us-east-1 --name vision-dev
```

**Option C: AWS Cloud9 / EC2 Instance**
```bash
# Launch Cloud9 or EC2 in the same VPC
# Then access cluster from within VPC
```

#### 2. Access Application via Port Forward

```bash
# Port forward to API service
kubectl port-forward -n vision-app svc/vision-api 8000:8000

# Access locally
curl http://localhost:8000/health
```

### AWS EKS - Production

#### 1. Deploy Infrastructure with CloudFront

```bash
cd terraform
terraform apply -var-file=environments/prod.tfvars
```

CloudFront is automatically configured to:
- Route traffic to internal ALB
- Add custom header for origin validation
- Apply WAF rules (rate limiting, common exploits)
- Cache static assets

#### 2. Update ALB with CDN Secret

```bash
# Get CDN secret from Secrets Manager
CDN_SECRET=$(aws secretsmanager get-secret-value --secret-id vision-prod-cdn-secret --query SecretString --output text)

# Update ingress annotation (already in values-prod.yaml)
# ALB will validate X-Custom-Header matches CDN_SECRET
```

#### 3. Access Application

```bash
# Get CloudFront domain
terraform output cloudfront_domain_name
# Output: d12345abcdef.cloudfront.net

# Access via CloudFront
curl https://d12345abcdef.cloudfront.net/health
```

**For custom domain:**
```bash
# Point your domain to CloudFront distribution
api.yourdomain.com -> CNAME -> d12345abcdef.cloudfront.net
```

### Azure AKS - Development

#### 1. Connect to Private Cluster

**Option A: VPN Connection (Recommended)**
```bash
# Setup Azure VPN Gateway to VNet
# Then configure kubectl
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
```

**Option B: Bastion Host**
```bash
# Use Azure Bastion to connect to VM in VNet
# From VM, configure kubectl
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
```

**Option C: Azure Cloud Shell**
```bash
# Cloud Shell can access private clusters via Azure network
az aks get-credentials --resource-group vision-dev-rg --name vision-dev-aks
```

#### 2. Access Application via Port Forward

```bash
# Port forward to API service
kubectl port-forward -n vision-app svc/vision-api 8000:8000

# Access locally
curl http://localhost:8000/health
```

### Azure AKS - Production

#### 1. Deploy Infrastructure with Front Door

```bash
cd terraform-aks
terraform apply -var-file=environments/prod.tfvars
```

Front Door is automatically configured to:
- Route traffic to internal load balancer via Private Link
- Apply WAF rules (rate limiting, bot protection, OWASP top 10)
- Cache static assets
- DDoS protection

#### 2. Access Application

```bash
# Get Front Door endpoint
terraform output frontdoor_endpoint_hostname
# Output: vision-prod-aks-endpoint-abc123.z01.azurefd.net

# Access via Front Door
curl https://vision-prod-aks-endpoint-abc123.z01.azurefd.net/health
```

**For custom domain:**
```bash
# Point your domain to Front Door endpoint
api.yourdomain.com -> CNAME -> vision-prod-aks-endpoint-abc123.z01.azurefd.net
```

## Security Benefits

### Private Clusters

1. **No Public API Access**
   - Kubernetes API server not exposed to internet
   - Reduces attack surface significantly
   - Only accessible from within VPC/VNet

2. **Network Isolation**
   - All nodes in private subnets
   - No direct internet access to nodes
   - Egress only through NAT Gateway

3. **Defense in Depth**
   - Multiple layers of security
   - VPN/Bastion required for cluster access
   - CDN validates all incoming requests

### CDN Protection (Production)

1. **DDoS Protection**
   - CloudFront/Front Door absorb attacks
   - Automatic scaling to handle traffic spikes
   - No direct access to origin (ALB/Internal LB)

2. **WAF Rules**
   - Rate limiting (2000 req/min AWS, 100 req/min Azure)
   - Common exploits blocked (SQL injection, XSS)
   - Bot protection
   - Geo-blocking (optional)

3. **Origin Validation**
   - Custom header from CDN to origin
   - ALB/LB validates header before routing
   - Prevents direct access to internal LB

4. **TLS Termination**
   - HTTPS at CDN edge
   - Can use HTTP internally (within VPC/VNet)
   - Reduces load on backend

## Cost Considerations

### Development
- **No CDN costs** - Just port-forward
- **VPN costs**: ~$73/month (AWS Client VPN) or ~$25/month (Azure VPN Gateway Basic)
- **Bastion costs**: ~$85/month (AWS) or ~$35/month (Azure)

### Production

**AWS CloudFront:**
- Data transfer out: $0.085/GB (first 10TB)
- Requests: $0.0075 per 10,000 HTTPS requests
- WAF: $5/month + $1 per rule + $0.60 per million requests
- **Estimated**: ~$100-300/month for moderate traffic

**Azure Front Door:**
- Standard: $35/month base + $0.06/GB outbound + $0.0055 per 10k requests
- Premium: $330/month base + same per-use pricing (includes WAF)
- **Estimated**: ~$150-400/month for moderate traffic

## Troubleshooting

### Cannot connect to cluster

```bash
# AWS - Check if in VPC
aws ec2 describe-instances --instance-ids $(ec2-metadata --instance-id)

# Azure - Check if in VNet
az vm list --query "[].{name:name, vnet:networkProfile.networkInterfaces[0].id}"

# Verify private DNS resolution
nslookup <cluster-api-endpoint>
```

### Port forward fails

```bash
# Check if pods are running
kubectl get pods -n vision-app

# Check service exists
kubectl get svc -n vision-app

# Verbose output
kubectl port-forward -v=9 -n vision-app svc/vision-api 8000:8000
```

### CDN cannot reach origin

```bash
# AWS - Check ALB health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Azure - Check backend health
az network application-gateway show-backend-health --name <agw-name> --resource-group <rg>

# Verify custom header is set
curl -H "X-Custom-Header: <secret>" https://internal-lb-endpoint/health
```

### CDN requests blocked by WAF

```bash
# AWS - Check WAF logs
aws wafv2 get-sampled-requests --web-acl-id <acl-id> --scope CLOUDFRONT

# Azure - Check Front Door logs
az monitor diagnostic-settings create --resource <frontdoor-id> --logs '[{"category": "FrontDoorAccessLog", "enabled": true}]'

# Temporarily set WAF to detection mode
# AWS: Change "action" from "block" to "count"
# Azure: Change "mode" from "Prevention" to "Detection"
```

## Best Practices

1. **Always use VPN for cluster access** in production
2. **Rotate CDN secrets regularly** (90 days)
3. **Monitor WAF logs** for attack patterns
4. **Use custom domains with SSL certificates** for production
5. **Enable CloudWatch/Azure Monitor logging** for all components
6. **Test failover scenarios** regularly
7. **Document VPN/Bastion access procedures** for team
8. **Use separate AWS/Azure accounts** for dev and prod

## Next Steps

1. Setup VPN connection for dev cluster access
2. Deploy application via helmfile
3. Test port-forward access in dev
4. Configure custom domain for prod CDN
5. Setup monitoring and alerting
6. Document runbooks for common operations

---

**Security Note**: Never expose Kubernetes API publicly. Always use private clusters with VPN/Bastion access for management, and CDN for public-facing applications.
