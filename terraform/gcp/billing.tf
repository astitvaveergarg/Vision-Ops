# Look up the numeric project number (required by billing budget API)
data "google_project" "current" {
  project_id = var.project_id
}

# ============================================================
# Pub/Sub Topic for Budget Alerts
# ============================================================

resource "google_pubsub_topic" "budget_alerts" {
  name    = "${var.cluster_name}-budget-alerts"
  project = var.project_id

  message_retention_duration = "604800s"

  depends_on = [google_project_service.required_apis]
}

# ============================================================
# Budget with email notifications to billing admins
# ============================================================

resource "google_billing_budget" "project_budget" {
  billing_account = var.billing_account_id
  display_name    = "VisionOps ${var.environment} - ${var.budget_amount} limit"

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
  }

  amount {
    specified_amount {
      # No currency_code — GCP uses the billing account's native currency
      units = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic                   = google_pubsub_topic.budget_alerts.id
    disable_default_iam_recipients = false
  }

  depends_on = [google_project_service.required_apis]
}
