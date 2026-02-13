# Resource Group Outputs
output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.aks.name
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.aks.location
}

# Network Outputs
output "vnet_id" {
  description = "Virtual network ID"
  value       = azurerm_virtual_network.aks.id
}

output "subnet_id" {
  description = "AKS subnet ID"
  value       = azurerm_subnet.aks.id
}

# AKS Outputs
output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "cluster_fqdn" {
  description = "AKS cluster FQDN"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "kube_config" {
  description = "Kubernetes configuration"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "cluster_identity" {
  description = "AKS cluster managed identity"
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "kubelet_identity" {
  description = "AKS kubelet managed identity"
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Node Pool Outputs
output "node_resource_group" {
  description = "Auto-created resource group for AKS nodes"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "default_node_pool_id" {
  description = "Default node pool ID"
  value       = azurerm_kubernetes_cluster.aks.default_node_pool[0].id
}

output "additional_node_pools" {
  description = "Additional node pool IDs"
  value       = { for k, v in azurerm_kubernetes_cluster_node_pool.additional : k => v.id }
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.aks[0].id : null
}

# Configuration Commands
output "configure_kubectl" {
  description = "Configure kubectl command"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "helm_deploy_command" {
  description = "Helmfile deploy command"
  value       = "helmfile -e ${var.environment} apply"
}
