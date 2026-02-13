# Resource Group
resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = "VisionOps"
    }
  )
}

# Virtual Network
resource "azurerm_virtual_network" "aks" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.subnet_cidr]
}

# Log Analytics Workspace for Monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30

  tags = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                    = var.cluster_name
  location                = azurerm_resource_group.aks.location
  resource_group_name     = azurerm_resource_group.aks.name
  dns_prefix              = var.dns_prefix
  kubernetes_version      = var.kubernetes_version
  private_cluster_enabled = true

  # Default Node Pool
  default_node_pool {
    name                = var.default_node_pool.name
    node_count          = var.default_node_pool.enable_auto_scaling ? null : var.default_node_pool.node_count
    min_count           = var.default_node_pool.enable_auto_scaling ? var.default_node_pool.min_count : null
    max_count           = var.default_node_pool.enable_auto_scaling ? var.default_node_pool.max_count : null
    vm_size             = var.default_node_pool.vm_size
    enable_auto_scaling = var.default_node_pool.enable_auto_scaling
    os_disk_size_gb     = var.default_node_pool.os_disk_size_gb
    vnet_subnet_id      = azurerm_subnet.aks.id
    zones               = var.default_node_pool.zones

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Managed Identity
  identity {
    type = "SystemAssigned"
  }

  # Network Profile
  network_profile {
    network_plugin    = var.network_plugin
    network_policy    = var.network_policy
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    load_balancer_sku = "standard"
  }

  # Azure AD Integration
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_ad ? [1] : []
    content {
      managed                = true
      azure_rbac_enabled     = true
      admin_group_object_ids = var.azure_ad_admin_group_ids
    }
  }

  # Monitoring
  dynamic "oms_agent" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.aks[0].id
    }
  }

  # Auto-upgrade channel
  automatic_channel_upgrade = var.environment == "prod" ? "stable" : "patch"

  # Azure Policy
  azure_policy_enabled = var.environment == "prod" ? true : false

  # Key Vault Secrets Provider
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = var.tags
}

# Additional Node Pools
resource "azurerm_kubernetes_cluster_node_pool" "additional" {
  for_each = var.additional_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = each.value.vm_size
  node_count            = each.value.enable_auto_scaling ? null : each.value.node_count
  min_count             = each.value.enable_auto_scaling ? each.value.min_count : null
  max_count             = each.value.enable_auto_scaling ? each.value.max_count : null
  enable_auto_scaling   = each.value.enable_auto_scaling
  os_disk_size_gb       = each.value.os_disk_size_gb
  vnet_subnet_id        = azurerm_subnet.aks.id
  zones                 = each.value.zones
  mode                  = each.value.mode
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags
}

# Role Assignment for Network Contributor
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# StorageClass for Azure Disk Premium
resource "kubernetes_storage_class_v1" "premium" {
  depends_on = [azurerm_kubernetes_cluster.aks]

  metadata {
    name = "managed-premium"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    skuName = "Premium_LRS"
    kind    = "Managed"
  }
}

# Remove default StorageClass
resource "null_resource" "remove_default_storage" {
  depends_on = [kubernetes_storage_class_v1.premium]

  provisioner "local-exec" {
    command = "kubectl annotate storageclass default storageclass.kubernetes.io/is-default-class=false --overwrite || true"
  }
}
