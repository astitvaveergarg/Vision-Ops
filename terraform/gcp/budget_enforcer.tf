# ============================================================
# Budget Enforcer Cloud Function
#
# Triggered by the billing budget Pub/Sub topic.
# At 100% spend it calls cloudbilling.projects.updateBillingInfo
# with an empty billingAccountName — unlinking the project from
# billing and halting all charges immediately.
#
# To re-enable billing:
#   GCP Console → Billing → My Projects → Re-link the project
# ============================================================

# -- Zip the function source ----------------------------------------------

data "archive_file" "budget_enforcer" {
  type        = "zip"
  source_dir  = "${path.module}/functions/budget_enforcer"
  output_path = "${path.module}/functions/budget_enforcer.zip"
}

# -- GCS bucket for function source ---------------------------------------

resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-fn-src-${substr(md5(var.project_id), 0, 6)}"
  location                    = var.gcp_region
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket_object" "budget_enforcer_zip" {
  name   = "budget_enforcer_${data.archive_file.budget_enforcer.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.budget_enforcer.output_path
}

# -- Dedicated service account for the function ---------------------------

resource "google_service_account" "budget_enforcer" {
  account_id   = "${var.cluster_name}-budget-fn"
  display_name = "Budget Enforcer Cloud Function"
  project      = var.project_id
}

# Allow the function SA to remove billing from the project (project-level role)
resource "google_project_iam_member" "budget_enforcer_billing_admin" {
  project = var.project_id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${google_service_account.budget_enforcer.email}"

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Build SA access to Artifact Registry (required for Gen 1 function build)
resource "google_project_iam_member" "cloudbuild_artifactregistry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# -- Cloud Function (Gen 1) with Pub/Sub trigger --------------------------

resource "google_cloudfunctions_function" "budget_enforcer" {
  name        = "${var.cluster_name}-budget-enforcer"
  description = "Disables project billing when spend reaches 100% of budget"
  project     = var.project_id
  region      = var.gcp_region

  runtime               = "python311"
  available_memory_mb   = 256
  timeout               = 60
  entry_point           = "disable_billing_if_over_budget"
  service_account_email = google_service_account.budget_enforcer.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.budget_enforcer_zip.name

  environment_variables = {
    GCP_PROJECT_ID = var.project_id
  }

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.budget_alerts.id
    failure_policy {
      retry = false # Don't retry — disabling billing is idempotent but noisy
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloudbuild_artifactregistry_reader,
  ]
}
