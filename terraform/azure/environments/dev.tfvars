# Development Environment Configuration

# REPLACE WITH YOUR SUBSCRIPTION ID
subscription_id = "00000000-0000-0000-0000-000000000000"

environment         = "dev"
location            = "eastus"
resource_group_name = "vision-dev-rg"

cluster_name       = "vision-dev-aks"
kubernetes_version = "1.28"
dns_prefix         = "vision-dev"

# Network Configuration
vnet_cidr      = "10.0.0.0/16"
subnet_cidr    = "10.0.1.0/24"
service_cidr   = "10.1.0.0/16"
dns_service_ip = "10.1.0.10"

network_plugin = "azure"
network_policy = "azure"

# Default Node Pool (System)
default_node_pool = {
  name                = "system"
  node_count          = 2
  min_count           = 2
  max_count           = 4
  vm_size             = "Standard_D4s_v3" # 4 vCPU, 16GB RAM
  enable_auto_scaling = true
  os_disk_size_gb     = 100
  zones               = ["1", "2"]
}

# Additional Node Pools
additional_node_pools = {
  # General workload pool
  general = {
    node_count          = 1
    min_count           = 1
    max_count           = 3
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    os_disk_size_gb     = 100
    zones               = ["1", "2"]
    mode                = "User"
    node_labels = {
      role = "general"
    }
    node_taints = []
  }

  # ML inference pool
  ml = {
    node_count          = 1
    min_count           = 1
    max_count           = 3
    vm_size             = "Standard_F8s_v2" # 8 vCPU, 16GB RAM, CPU-optimized
    enable_auto_scaling = true
    os_disk_size_gb     = 200
    zones               = ["1"]
    mode                = "User"
    node_labels = {
      role     = "ml"
      workload = "inference"
    }
    node_taints = []
  }
}

# Monitoring
enable_monitoring = true

# CDN
enable_frontdoor = false # Dev uses port-forward

# Azure AD Integration
enable_azure_ad = false # Set to true and provide admin group IDs for production

tags = {
  Environment = "dev"
  CostCenter  = "engineering"
  Owner       = "devops-team"
  Terraform   = "true"
}
