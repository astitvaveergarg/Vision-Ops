# Terraform - AWS EKS

> ⏳ **Status: IaC complete. Cluster not yet provisioned.**
> Active deployment is on GCP GKE. See `terraform/gcp/README.md`.

Terraform configuration for provisioning AWS EKS for VisionOps.

---

## Infrastructure Components

### VPC
- CIDR: `10.0.0.0/16` (dev), `10.1.0.0/16` (prod)
- Private + public subnets across 2-3 AZs
- NAT Gateway (single dev, multi-AZ prod)
- Kubernetes ELB discovery tags

### EKS Cluster
- Version: 1.28
- Private API endpoint (no public access)
- IRSA enabled for pod-level IAM
- Addons: CoreDNS, kube-proxy, VPC-CNI, EBS CSI

### Node Groups

**Dev:**
- `general`: 2-5× t3.large, ON_DEMAND
- `ml`: 1-3× c5.2xlarge, SPOT (CPU-optimised)

**Prod:**
- `general`: 3-6× t3.xlarge, ON_DEMAND
- `ml`: 2-10× c5.4xlarge, ON_DEMAND
- `monitoring`: 2-3× t3.large, ON_DEMAND

### CDN + WAF (Prod)
- CloudFront distribution → Internal ALB
- Custom origin header validation (blocks direct ALB access)
- WAF rules: rate limiting (2000 req/min), OWASP common rules

### Storage
- StorageClass: `gp3` (EBS)
- EBS CSI Driver, encryption enabled

---

## Directory Structure

```
terraform/aws/
├── main.tf                 # Provider, S3 backend, required versions
├── variables.tf            # Input variables
├── outputs.tf              # Outputs: cluster_name, kubeconfig command, cloudfront_domain
├── eks.tf                  # EKS cluster, node groups, IRSA
├── cloudfront.tf           # CloudFront + WAF (prod only)
├── environments/
│   ├── dev.tfvars
│   └── prod.tfvars
├── COMMANDS.md
└── README.md
```

---

## Prerequisites

```bash
# AWS CLI
aws configure   # set Access Key, Secret, region (us-east-1)

# Verify
aws sts get-caller-identity
```

---

## Deploy Dev Cluster

```bash
# 1. Create Terraform state backend
aws s3 mb s3://vision-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket vision-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name vision-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# 2. Deploy
cd terraform/aws
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
# ~15-20 minutes

# 3. Configure kubectl (from inside VPC/VPN — private endpoint)
aws eks update-kubeconfig --region us-east-1 --name vision-dev
```

> **Access**: API server endpoint is private. Requires VPN or bastion.
> See `PRIVATE_CLUSTER_GUIDE.md` for setup.

---

## Deploy VisionOps to EKS

```bash
# Install ALB Controller (required for ingress)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=vision-dev \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<alb-iam-role-arn>

# Create namespaces + secrets (use strong random values)
kubectl create namespace vision-infra
kubectl create namespace vision-app
kubectl create namespace vision-monitoring

# Apply secrets — see k8s/secrets-dev.yaml.example
kubectl apply -f k8s/secrets-dev.yaml

# Deploy
helmfile -e dev sync
```

**Note**: Use `gp3` storage class for EKS (already set in `charts/api/values-dev.yaml` when targeting AWS).
For GKE, it must be `standard`.

---

## Cost Estimates

| Environment | Nodes | Estimated cost |
|-------------|-------|----------------|
| Dev | 2× t3.large + 1× c5.2xlarge | ~$200-300/month |
| Prod | 3× t3.xlarge + 2× c5.4xlarge | ~$1,200-1,500/month |

> Destroy when not in use: `terraform destroy -var-file=environments/dev.tfvars`

---

## Destroy

```bash
helmfile -e dev destroy
cd terraform/aws
terraform destroy -var-file=environments/dev.tfvars
```
