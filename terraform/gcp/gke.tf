# ============================================================
# VPC Network
# ============================================================

resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "gke" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true

  # Secondary ranges for GKE pods and services (VPC-native cluster)
  secondary_ip_range {
    range_name    = "${var.cluster_name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.cluster_name}-services"
    ip_cidr_range = var.services_cidr
  }
}

# Cloud Router + NAT for private nodes to pull images
resource "google_compute_router" "nat_router" {
  name    = "${var.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.gcp_region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}

# ============================================================
# GKE Service Account
# ============================================================

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "VisionOps GKE Node Service Account"
  project      = var.project_id
}

# Minimal permissions for GKE nodes
resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",       # Pull images from Artifact Registry
    "roles/artifactregistry.reader",    # Optional: if using Artifact Registry
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ============================================================
# GKE Cluster
# ============================================================

resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.cluster_location   # Zone (e.g. us-central1-a) = free control plane
  project  = var.project_id

  # Remove default node pool — we manage node pools separately
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native networking (required for private cluster)
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.gke.name

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.cluster_name}-pods"
    services_secondary_range_name = "${var.cluster_name}-services"
  }

  # Private cluster — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false   # Keep public endpoint for kubectl access
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  # Allow kubectl from anywhere (tighten in prod with authorized networks)
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity — pods can authenticate to GCP APIs without keys
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Cluster addons
  addons_config {
    http_load_balancing {
      disabled = false   # Enables GKE Ingress
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true     # Enables StorageClass for PVCs
    }
  }

  # Logging & monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Release channel — get automatic K8s minor version upgrades
  release_channel {
    channel = var.environment == "prod" ? "STABLE" : "REGULAR"
  }

  # Maintenance window — daily 4hr window satisfies GKE's >=48hr/32day requirement
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=DAILY"
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.gke,
  ]
}

# ============================================================
# Node Pools
# ============================================================

# General node pool — runs Redis, MinIO, Prometheus, Grafana
resource "google_container_node_pool" "general" {
  name     = "general"
  location = var.cluster_location
  cluster  = google_container_cluster.gke.name
  project  = var.project_id

  initial_node_count = var.general_node_pool.min_count

  autoscaling {
    min_node_count = var.general_node_pool.min_count
    max_node_count = var.general_node_pool.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.general_node_pool.machine_type
    disk_size_gb = var.general_node_pool.disk_size_gb
    disk_type    = "pd-ssd"

    # Use spot instances in dev to save cost
    spot = var.general_node_pool.use_spot

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(
      { role = "general" },
      var.general_node_pool.labels
    )

    shielded_instance_config {
      enable_secure_boot = true
    }
  }
}

# ML node pool — runs vision-api (YOLO inference)
resource "google_container_node_pool" "ml" {
  name     = "ml"
  location = var.cluster_location
  cluster  = google_container_cluster.gke.name
  project  = var.project_id

  initial_node_count = var.ml_node_pool.min_count

  autoscaling {
    min_node_count = var.ml_node_pool.min_count
    max_node_count = var.ml_node_pool.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.ml_node_pool.machine_type
    disk_size_gb = var.ml_node_pool.disk_size_gb
    disk_type    = "pd-ssd"

    spot = var.ml_node_pool.use_spot

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(
      {
        role     = "ml"
        workload = "inference"
      },
      var.ml_node_pool.labels
    )

    # Taint ML nodes so only vision-api pods land here
    dynamic "taint" {
      for_each = var.ml_node_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    shielded_instance_config {
      enable_secure_boot = true
    }
  }
}

# NOTE: GKE automatically creates these StorageClasses — no manual creation needed:
#   standard-rwo  → pd-balanced (default)
#   premium-rwo   → pd-ssd
# Use 'premium-rwo' in Helm values for Redis/MinIO PVCs.
