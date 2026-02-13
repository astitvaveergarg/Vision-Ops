# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# EKS Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(module.eks.cluster_oidc_issuer_url, "")
}

# Node Group Outputs
output "node_group_arns" {
  description = "ARNs of the EKS node groups"
  value       = { for k, v in module.eks.eks_managed_node_groups : k => v.node_group_arn }
}

output "node_group_status" {
  description = "Status of the EKS node groups"
  value       = { for k, v in module.eks.eks_managed_node_groups : k => v.node_group_status }
}

# IAM Outputs
output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = try(module.ebs_csi_irsa_role.iam_role_arn, "")
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for ALB controller"
  value       = try(module.alb_controller_irsa_role.iam_role_arn, "")
}

# Configuration Commands
output "configure_kubectl" {
  description = "Configure kubectl command"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "helm_deploy_command" {
  description = "Helmfile deploy command"
  value       = "helmfile -e ${var.environment} apply"
}
