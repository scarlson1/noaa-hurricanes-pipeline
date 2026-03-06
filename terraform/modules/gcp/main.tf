# Service account for Kestra to authenticate with GCP
resource "google_service_account" "kestra" {
  account_id   = "kestra-sa"
  display_name = "Kestra Service Account"
}

# GCS bucket (already exists — will import)
resource "google_storage_bucket" "kestra_bucket" {
  name     = var.gcs_bucket_name
  location = "US"

  versioning { enabled = true }

  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 90 }
  }
}

# IAM: SA can read/write GCS (Kestra internal bucket)
resource "google_storage_bucket_iam_member" "kestra_gcs" {
  bucket = google_storage_bucket.kestra_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.kestra.email}"
}

# IAM: SA can read/write hurricane data bucket
resource "google_storage_bucket_iam_member" "kestra_hurricane_data_gcs" {
  bucket = "hurricane_data_noaa"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.kestra.email}"
}

# BigQuery dataset (already exists — will import)
resource "google_bigquery_dataset" "kestra_dataset" {
  dataset_id = var.bq_dataset_id
  location   = "US"
}

# IAM: SA can read/write BQ
resource "google_bigquery_dataset_iam_member" "kestra_bq" {
  dataset_id = google_bigquery_dataset.kestra_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.kestra.email}"
}

# Also grant BQ job runner (needed to actually run queries)
resource "google_project_iam_member" "kestra_bq_jobs" {
  project = var.gcp_project
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.kestra.email}"
}

# Generate a key for the SA (used in Kestra plugin config)
resource "google_service_account_key" "kestra_key" {
  service_account_id = google_service_account.kestra.name
}

output "kestra_sa_key" {
  value     = google_service_account_key.kestra_key.private_key
  sensitive = true
}