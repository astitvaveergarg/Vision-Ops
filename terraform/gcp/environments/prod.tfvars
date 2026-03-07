# Production Environment Configuration
# Regional cluster = HA control plane ($0.10/hr = $72/month)
# Estimated cost: ~$0.65/hr = ~$15.60/day while running (3 nodes)

# REPLACE WITH YOUR GCP PROJECT ID
project_id = "your-gcp-project-id"

environment = "prod"
gcp_region  = "us-central1"

# Regional location = multi-zone HA (nodes spread across us-central1-a/b/c)
cluster_location = "us-central1"
cluster_name     = "vision-prod-gke"

# Network Configuration
subnet_cidr      = "10.10.0.0/24"
pods_cidr        = "10.11.0.0/16"
services_cidr    = "10.12.0.0/20"
master_ipv4_cidr = "172.16.1.0/28"

# Restrict kubectl access to known IPs in prod
# Replace with your VPN/office/bastion IP
master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "Replace with your IP/VPN CIDR"
  }
]

# General node pool — runs Redis, MinIO, Prometheus, Grafana
# e2-standard-4: 4 vCPU, 16GB RAM = $0.134/hr each
general_node_pool = {
  machine_type = "e2-standard-4"
  min_count    = 2
  max_count    = 5
  disk_size_gb = 100
  use_spot     = false   # ON_DEMAND for prod stability
  labels       = {}
}

# ML node pool — runs vision-api (YOLO inference)
# c2-standard-8: 8 vCPU, 32GB RAM — CPU-optimized for inference = $0.334/hr each
ml_node_pool = {
  machine_type = "c2-standard-8"
  min_count    = 2
  max_count    = 10
  disk_size_gb = 200
  use_spot     = false
  labels = {
    workload = "inference"
  }
  taints = [
    {
      key    = "workload"
      value  = "ml"
      effect = "NO_SCHEDULE"
    }
  ]
}

# Cloud Armor WAF enabled in prod
enable_cloud_armor = true

# Billing & Budget
# Find your billing account ID: gcloud billing accounts list
billing_account_id = "01D519-3FDECB-482363"
budget_amount      = 250
