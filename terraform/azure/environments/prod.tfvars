# Production Environment Configuration

# REPLACE WITH YOUR SUBSCRIPTION ID
subscription_id = "00000000-0000-0000-0000-000000000000"

environment         = "prod"
location            = "eastus"
resource_group_name = "vision-prod-rg"

cluster_name       = "vision-prod-aks"
kubernetes_version = "1.28"
dns_prefix         = "vision-prod"

# Network Configuration
vnet_cidr      = "10.1.0.0/16"
subnet_cidr    = "10.1.1.0/24"
service_cidr   = "10.2.0.0/16"
dns_service_ip = "10.2.0.10"

network_plugin = "azure"
network_policy = "azure"

# Default Node Pool (System)
default_node_pool = {
  name                = "system"
  node_count          = 3
  min_count           = 3
  max_count           = 6
  vm_size             = "Standard_D8s_v3" # 8 vCPU, 32GB RAM
  enable_auto_scaling = true
  os_disk_size_gb     = 128
  zones               = ["1", "2", "3"]
}

# Additional Node Pools
additional_node_pools = {
  # General workload pool
  general = {
    node_count          = 2
    min_count           = 2
    max_count           = 5
    vm_size             = "Standard_D8s_v3"
    enable_auto_scaling = true
    os_disk_size_gb     = 128
    zones               = ["1", "2", "3"]
    mode                = "User"
    node_labels = {
      role = "general"
    }
    node_taints = []
  }

  # ML inference pool
  ml = {
    node_count          = 2
    min_count           = 2
    max_count           = 10
    vm_size             = "Standard_F16s_v2" # 16 vCPU, 32GB RAM, CPU-optimized
    enable_auto_scaling = true
    os_disk_size_gb     = 256
    zones               = ["1", "2", "3"]
    mode                = "User"
    node_labels = {
      role     = "ml"
      workload = "inference"
    }
    node_taints = [
      "workload=ml:NoSchedule"
    ]
  }

  # Monitoring pool
  monitoring = {
    node_count          = 2
    min_count           = 2
    max_count           = 3
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    os_disk_size_gb     = 128
    zones               = ["1", "2"]
    mode                = "User"
    node_labels = {
      role = "monitoring"
    }
    node_taints = []
  }
}

# Monitoring
enable_monitoring = true

# CDN
enable_frontdoor = true # Prod uses Azure Front Door

# Azure AD Integration
enable_azure_ad = true
# REPLACE WITH YOUR AZURE AD GROUP OBJECT IDs
azure_ad_admin_group_ids = [
  # "00000000-0000-0000-0000-000000000000"
]

tags = {
  Environment      = "prod"
  CostCenter       = "production"
  Owner            = "platform-team"
  Compliance       = "required"
  BackupPolicy     = "daily"
  DisasterRecovery = "12h-rto"
  Terraform        = "true"
}
