variable "gcp_project" {
  description = "GCP project ID"
}

variable "gcp_region" {
  description = "GCP region"
  default     = "us-central1"
}

variable "gcs_bucket_name" {
  description = "Name of the existing GCS bucket for Kestra storage"
  default     = "hurricanes_pipeline_kestra"
}

variable "bq_dataset_id" {
  description = "BigQuery dataset ID"
}