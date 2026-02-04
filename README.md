# NOAA Hurricane data pipeline

### NOAA Best Track Data --> BigQuery --> Cockroach DB

---

### [01_gcp_kv.yaml](./flows/01_gcp_kv.yaml)

Load cloud variables (project ID, BigQuery dataset, etc)

### [02_gcp_setup.yaml](./flows/02_gcp_setup.yaml)

- create GCP Bucket
- create BigQuery dataset

### [03_gcp_paths.yaml](./flows/03_gcp_paths.yaml)

- Select NOAA dataset to download (basin) and year to filter
- downloads CSV to GCS
- creates BigQuery table if it doesn't exist
- creates *EXTERNAL* BigQuery table from GCS CSV
- creates materialize BigQuery table
  - filters from input (basin, year)
  - calculates unique row ID (hash of sid + timestamp)
- merges table into target_table if row doesn't already exist

### [04_gcp_cockreachdb.yaml](./flows/04_gcp_cockroachdb.yaml)

- creates BigQuery Table from inputs (min category, year)
- exports to GCS as CSV
- creates staging table in CockroachDB & copies from CSV
- inserts rows into destination table (if `unique_row_id` doesn't exist)
- truncate staging table
