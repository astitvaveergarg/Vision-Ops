# Development Environment Configuration
# Zonal cluster = FREE control plane ($0.00/hr for control plane)
# Estimated cost: ~$0.16/hr = ~$3.84/day while running

# REPLACE WITH YOUR GCP PROJECT ID
project_id = "vision-ops-demo"

environment = "dev"
gcp_region  = "us-central1"

# Zonal location = free GKE control plane
cluster_location = "us-central1-a"
cluster_name     = "vision-dev-gke"

# Network Configuration
subnet_cidr      = "10.0.0.0/24"
pods_cidr        = "10.1.0.0/16"
services_cidr    = "10.2.0.0/20"
master_ipv4_cidr = "172.16.0.0/28"

# Allow kubectl from anywhere in dev (restrict to your IP in prod)
master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "All (dev only)"
  }
]

# General node pool — runs Redis, MinIO, Prometheus, Grafana
# e2-standard-4: 4 vCPU, 16GB RAM = $0.134/hr
general_node_pool = {
  machine_type = "e2-standard-4"
  min_count    = 1
  max_count    = 2
  disk_size_gb = 100
  use_spot     = false   # Spot saves ~60-91%, but nodes can be preempted
  labels       = {}
}

# ML node pool — runs vision-api (YOLO inference)
# e2-standard-4: 4 vCPU, 16GB RAM = $0.134/hr
# Combined with infra on same machine type to keep dev costs low
ml_node_pool = {
  machine_type = "e2-standard-4"
  min_count    = 1
  max_count    = 3
  disk_size_gb = 100
  use_spot     = false
  labels       = {}
  taints       = []   # No taints in dev — simpler scheduling
}

# Cloud Armor disabled in dev (no public LB needed, use port-forward)
enable_cloud_armor = false

# Billing & Budget
# Find your billing account ID: gcloud billing accounts list
billing_account_id = "01D519-3FDECB-482363"
budget_amount      = 22500
