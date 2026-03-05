# variables.tf
variable "oci_tenancy_ocid" { sensitive = true }
variable "oci_user_ocid" { sensitive = true }
variable "oci_fingerprint" { sensitive = true }
variable "oci_private_key_path" {}
variable "oci_region" { default = "us-chicago-1" }
variable "oci_compartment_ocid" {}
variable "oci_availability_domain" {}
variable "oci_vm_image_ocid" {}

variable "gcp_project" {}
variable "gcp_region" { default = "us-central1" }
variable "gcp_credentials_file" { sensitive = true }
variable "gcs_bucket_name" { default = "hurricanes_pipeline_kestra" }
variable "bq_dataset_id" {}