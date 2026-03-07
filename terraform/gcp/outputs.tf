# Network Outputs
output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "VPC network self link"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = google_compute_subnetwork.gke.name
}

# GKE Cluster Outputs
output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.gke.name
}

output "cluster_location" {
  description = "GKE cluster location (zone or region)"
  value       = google_container_cluster.gke.location
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.gke.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64)"
  value       = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.gke.id
}

# Node Pool Outputs
output "general_node_pool_name" {
  description = "General node pool name"
  value       = google_container_node_pool.general.name
}

output "ml_node_pool_name" {
  description = "ML node pool name"
  value       = google_container_node_pool.ml.name
}

# Service Account
output "node_service_account_email" {
  description = "GKE node service account email"
  value       = google_service_account.gke_nodes.email
}

# Cloud Armor Outputs (prod only)
output "cloud_armor_policy_name" {
  description = "Cloud Armor security policy name"
  value       = var.enable_cloud_armor ? google_compute_security_policy.api[0].name : "not enabled"
}

# Configuration Commands
output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke.name} --location ${google_container_cluster.gke.location} --project ${var.project_id}"
}

output "helm_deploy_command" {
  description = "Helmfile deploy command"
  value       = "helmfile -e ${var.environment} apply"
}

# Budget & Pub/Sub Outputs
output "budget_pubsub_topic" {
  description = "Pub/Sub topic receiving budget alert notifications"
  value       = google_pubsub_topic.budget_alerts.id
}

output "budget_display_name" {
  description = "Billing budget name"
  value       = google_billing_budget.project_budget.display_name
}
output "create_namespaces_command" {
  description = "Create required Kubernetes namespaces"
  value       = "kubectl create namespace vision-infra ; kubectl create namespace vision-app ; kubectl create namespace vision-monitoring"
}
