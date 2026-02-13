# Azure Subscription
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# Environment
variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either dev or prod."
  }
}

# Location
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

# Resource Group
variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

# Cluster Configuration
variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "dns_prefix" {
  description = "DNS prefix for AKS cluster"
  type        = string
}

# Network Configuration
variable "vnet_cidr" {
  description = "CIDR block for VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.1.0.10"
}

# Node Pool Configuration
variable "default_node_pool" {
  description = "Default node pool configuration"
  type = object({
    name                = string
    node_count          = number
    min_count           = number
    max_count           = number
    vm_size             = string
    enable_auto_scaling = bool
    os_disk_size_gb     = number
    zones               = list(string)
  })
}

variable "additional_node_pools" {
  description = "Additional node pool configurations"
  type = map(object({
    node_count          = number
    min_count           = number
    max_count           = number
    vm_size             = string
    enable_auto_scaling = bool
    os_disk_size_gb     = number
    zones               = list(string)
    mode                = string
    node_labels         = map(string)
    node_taints         = list(string)
  }))
  default = {}
}

# Networking
variable "network_plugin" {
  description = "Network plugin (azure or kubenet)"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy (azure or calico)"
  type        = string
  default     = "azure"
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable Azure Monitor for containers"
  type        = bool
  default     = true
}

# Azure AD Integration
variable "enable_azure_ad" {
  description = "Enable Azure AD integration"
  type        = bool
  default     = true
}

variable "azure_ad_admin_group_ids" {
  description = "Azure AD group object IDs for cluster admin access"
  type        = list(string)
  default     = []
}

# CDN Configuration  
variable "enable_frontdoor" {
  description = "Enable Azure Front Door CDN for production"
  type        = bool
  default     = false
}

# Tags
variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
