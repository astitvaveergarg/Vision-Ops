# Production Environment Configuration

environment = "prod"
aws_region  = "us-east-1"

cluster_name    = "vision-prod"
cluster_version = "1.28"

vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Node Groups
node_groups = {
  # General purpose nodes (infrastructure)
  general = {
    desired_size   = 1
    min_size       = 1
    max_size       = 3
    instance_types = ["t3.xlarge"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels = {
      role = "general"
    }
    taints = []
  }

  # ML workload nodes (YOLO inference)
  ml = {
    desired_size   = 2
    min_size       = 2
    max_size       = 10
    instance_types = ["c5.4xlarge"] # 16 vCPU, 32GB RAM
    capacity_type  = "ON_DEMAND"
    disk_size      = 200
    labels = {
      role     = "ml"
      workload = "inference"
    }
    taints = [
      {
        key    = "workload"
        value  = "ml"
        effect = "NoSchedule"
      }
    ]
  }

  # Monitoring nodes
  monitoring = {
    desired_size   = 1
    min_size       = 1
    max_size       = 2
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels = {
      role = "monitoring"
    }
    taints = []
  }
}

# Addons
enable_ebs_csi_driver  = true
enable_alb_controller  = true
enable_cert_manager    = true
enable_monitoring      = true
enable_cloudfront      = true # Prod uses CloudFront CDN

tags = {
  Environment        = "prod"
  CostCenter         = "personal-production"
  Owner              = "astitvaveergarg"
  Compliance         = "required"
  BackupPolicy       = "daily"
  DisasterRecovery   = "12h-rto"
}
