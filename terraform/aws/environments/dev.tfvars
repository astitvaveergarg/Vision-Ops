# Development Environment Configuration

environment = "dev"
aws_region  = "us-east-1"

cluster_name    = "vision-dev"
cluster_version = "1.28"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# Node Groups
node_groups = {
  # General purpose nodes
  general = {
    desired_size   = 2
    min_size       = 2
    max_size       = 5
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels = {
      role = "general"
    }
    taints = []
  }

  # ML workload nodes (for YOLO inference)
  ml = {
    desired_size   = 1
    min_size       = 1
    max_size       = 3
    instance_types = ["c5.2xlarge"] # CPU-optimized for ML
    capacity_type  = "SPOT"         # Save cost on dev
    disk_size      = 100
    labels = {
      role     = "ml"
      workload = "inference"
    }
    taints = []
  }
}

# Addons
enable_ebs_csi_driver  = true
enable_alb_controller  = true
enable_cert_manager    = true
enable_monitoring      = true
enable_cloudfront      = false # Dev uses port-forward

tags = {
  Environment = "dev"
  CostCenter  = "personal-dev"
  Owner       = "astitvaveergarg"
}
