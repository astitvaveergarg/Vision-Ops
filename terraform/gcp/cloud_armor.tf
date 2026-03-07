# Cloud Armor Security Policy (GCP equivalent of CloudFront WAF / Azure WAF)
# Only created when var.enable_cloud_armor = true (recommended for prod)

resource "random_password" "cdn_secret" {
  count   = var.enable_cloud_armor ? 1 : 0
  length  = 32
  special = false
}

# Cloud Armor security policy with OWASP-based rules
resource "google_compute_security_policy" "api" {
  count   = var.enable_cloud_armor ? 1 : 0
  name    = "${var.cluster_name}-armor-policy"
  project = var.project_id

  description = "VisionOps API WAF policy - ${var.environment}"

  # Default allow rule (lowest priority)
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Block known malicious IPs (rate limit)
  rule {
    action   = "throttle"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    description = "Rate limit: 100 req/min per IP"
  }

  # OWASP Top 10 protection - SQL injection
  rule {
    action   = "deny(403)"
    priority = "100"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection attacks (OWASP)"
  }

  # OWASP Top 10 protection - XSS
  rule {
    action   = "deny(403)"
    priority = "200"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS attacks (OWASP)"
  }

  # OWASP Top 10 protection - Remote File Inclusion
  rule {
    action   = "deny(403)"
    priority = "300"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }
    description = "Block RFI attacks (OWASP)"
  }

  # OWASP Top 10 protection - Local File Inclusion
  rule {
    action   = "deny(403)"
    priority = "400"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }
    description = "Block LFI attacks (OWASP)"
  }
}

# Store the CDN secret in GCP Secret Manager (optional, for header-based auth)
resource "google_secret_manager_secret" "cdn_secret" {
  count     = var.enable_cloud_armor ? 1 : 0
  secret_id = "${var.cluster_name}-cdn-secret"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cdn_secret" {
  count       = var.enable_cloud_armor ? 1 : 0
  secret      = google_secret_manager_secret.cdn_secret[0].id
  secret_data = random_password.cdn_secret[0].result
}

# Output for Cloud Armor (referenced in outputs.tf)
# Note: Cloud Armor policy is attached to GKE ingress via BackendConfig annotation:
#
#   apiVersion: cloud.google.com/v1
#   kind: BackendConfig
#   metadata:
#     name: vision-api-backend-config
#     namespace: vision-app
#   spec:
#     securityPolicy:
#       name: <cloud_armor_policy_name>
#
# Then reference in Service:
#   annotations:
#     cloud.google.com/backend-config: '{"default": "vision-api-backend-config"}'
