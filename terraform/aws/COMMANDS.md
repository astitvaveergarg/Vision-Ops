# Quick Reference - AWS EKS Commands

> ⏳ IaC complete. Cluster not yet provisioned. Active deployment is GCP GKE.

## Prerequisites

```bash
aws configure   # set Access Key ID, Secret Access Key, region: us-east-1
aws sts get-caller-identity   # verify credentials
```

## Create State Backend (One-Time)

```bash
aws s3 mb s3://vision-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket vision-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name vision-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

## Dev Cluster

```bash
cd terraform/aws
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars   # ~15-20 min

# kubectl (must be inside VPC via VPN/bastion)
aws eks update-kubeconfig --region us-east-1 --name vision-dev
kubectl get nodes
```

## Deploy VisionOps

```bash
# Apply secrets first
kubectl apply -f k8s/secrets-dev.yaml

# Deploy
helmfile -e dev sync
kubectl get pods -A -w
```

## Destroy

```bash
helmfile -e dev destroy
cd terraform/aws
terraform destroy -var-file=environments/dev.tfvars   # ~10-15 min
```

## Prod Cluster

```bash
terraform apply  -var-file=environments/prod.tfvars
aws eks update-kubeconfig --region us-east-1 --name vision-prod
helmfile -e prod apply
terraform destroy -var-file=environments/prod.tfvars
```

## Useful AWS Commands

```bash
# List EKS clusters
aws eks list-clusters --region us-east-1

# Check node groups
aws eks list-nodegroups --cluster-name vision-dev --region us-east-1

# CloudFront distribution
aws cloudfront list-distributions | jq '.DistributionList.Items[].DomainName'

# Terraform outputs
terraform output cloudfront_domain_name
terraform output configure_kubectl
```
