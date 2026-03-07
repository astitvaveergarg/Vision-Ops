# GCP Project
variable "project_id" {
  description = "GCP project ID"
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

# Region & Location
variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "cluster_location" {
  description = "GKE cluster location. Zone (e.g. us-central1-a) = free control plane. Region (e.g. us-central1) = $0.10/hr but highly available."
  type        = string
  default     = "us-central1-a"
}

# Cluster Configuration
variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

# Network Configuration
variable "subnet_cidr" {
  description = "CIDR for GKE node subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary CIDR for GKE pods (VPC-native)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for GKE services (VPC-native)"
  type        = string
  default     = "10.2.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "CIDR for GKE control plane (must be /28, not overlapping with VPC)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of CIDRs allowed to reach the GKE API server"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All (restrict in prod)"
    }
  ]
}

# General Node Pool
variable "general_node_pool" {
  description = "General node pool config (runs infra: Redis, MinIO, Prometheus)"
  type = object({
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size_gb = number
    use_spot     = bool
    labels       = map(string)
  })
  default = {
    machine_type = "e2-standard-4"
    min_count    = 1
    max_count    = 3
    disk_size_gb = 100
    use_spot     = false
    labels       = {}
  }
}

# ML Node Pool
variable "ml_node_pool" {
  description = "ML node pool config (runs vision-api YOLO inference)"
  type = object({
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size_gb = number
    use_spot     = bool
    labels       = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  })
  default = {
    machine_type = "e2-standard-4"
    min_count    = 1
    max_count    = 5
    disk_size_gb = 100
    use_spot     = false
    labels       = {}
    taints       = []
  }
}

# Cloud Armor (GCP WAF — replaces CloudFront WAF / Azure WAF)
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor WAF security policy (recommended for prod)"
  type        = bool
  default     = false
}

# Billing & Budget
variable "billing_account_id" {
  description = "GCP billing account ID (format: XXXXXX-XXXXXX-XXXXXX). Find it at console.cloud.google.com/billing"
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget cap in USD. Alerts fire at 50%, 90%, 100%, 110%."
  type        = number
  default     = 250
}

# Tags/Labels
variable "labels" {
  description = "Additional GCP labels to apply to resources"
  type        = map(string)
  default     = {}
}
