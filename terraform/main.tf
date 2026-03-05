module "oci" {
  source              = "./modules/oci"
  compartment_ocid    = var.oci_compartment_ocid
  availability_domain = var.oci_availability_domain
  vm_image_ocid       = var.oci_vm_image_ocid
}

module "gcp" {
  source          = "./modules/gcp"
  gcp_project     = var.gcp_project
  gcp_region      = var.gcp_region
  gcs_bucket_name = var.gcs_bucket_name
  bq_dataset_id   = var.bq_dataset_id
}