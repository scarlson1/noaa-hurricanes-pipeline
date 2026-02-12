# NOAA Hurricane data pipeline

Google's BigQuery public dataset connection stopped updating sometime around 2024. This Kestra implementation is an ETL implementation to move NOAA best track data into a SQL database used by [this hurricane path website](https://historical-paths.web.app/).

### NOAA Best Track Data --> GCS --> BigQuery --> Cockroach DB

Resource Links:

- (NOAA v04r01 column documentation)[https://www.ncei.noaa.gov/sites/default/files/2025-09/IBTrACS_v04r01_column_documentation.pdf]
- (NOAA international best track archive)[https://www.ncei.noaa.gov/products/international-best-track-archive]
- (NOAA CSV data)[https://www.ncei.noaa.gov/data/international-best-track-archive-for-climate-stewardship-ibtracs/v04r01/access/csv/]

---

## Kestra Flows

### [01_gcp_kv.yaml](./flows/01_gcp_kv.yaml)

Load cloud variables (project ID, BigQuery dataset, etc)

### [02_gcp_setup.yaml](./flows/02_gcp_setup.yaml)

- create GCP Bucket
- create BigQuery dataset

### [03_gcp_paths.yaml](./flows/03_gcp_paths.yaml)

- Select NOAA dataset to download (basin) and year to filter
- downloads CSV to GCS
- creates BigQuery table if it doesn't exist
- creates _EXTERNAL_ BigQuery table from GCS CSV
- creates materialize BigQuery table
  - filters from input (basin, year)
  - calculates unique row ID (hash of sid + timestamp)
- merges table into BigQuery `target_table` if row doesn't already exist
- optionally drop materialized BigQuery table

### [04_gcp_cockreachdb.yaml](./flows/04_gcp_cockroachdb.yaml)

- creates BigQuery Table from inputs (min category, year)
- exports to GCS as CSV
- creates staging table in CockroachDB & copies from CSV
- inserts rows into destination table (if `unique_row_id` doesn't exist)
- truncate staging table

---

## Running Locally

**Secrets**

- GEMINI_KEY
- COCKROACH_PASSWORD
- SECRET_GCP_SERVICE_ACCOUNT

**Encoding secrets**

Run the following command to encode the Google Cloud service account key. (Kestra docs)[https://kestra.io/docs/how-to-guides/google-credentials]

```bash
echo SECRET_GCP_SERVICE_ACCOUNT=$(cat service-account.json | base64 -w 0) >> .env_encoded
```

Run the following command to encode string secrets (Gemini key, Cochroach password). Add to .env_encoded.

```bash
echo -n "actual_env_var" | base64
```

.env_encoded is referenced in the `docker-compose.yaml` file:

```yml
services:
  kestra:
    image: kestra/kestra:latest
    env_file:
      - .env_encoded
    # ... other configurations
```

**Start docker compose:**

```bash
docker compose up -d
```

**Upload Flows**

Flows can be created and edited from the dashboard or uploaded from an existing file:

```bash
# CLI:
kestra flow create /path/to/flow.yml
# API:
curl -X POST http://localhost:8080/api/v1/flows/import -F fileUpload=@flow.yaml
# with basic auth:
curl -X POST "http://localhost:8080/api/v1/flows" \
     -u "admin@kestra.io:kestra" \
     -H "Content-Type: application/yaml" \
     --data-binary "@my-flow.yaml"
```

(Open Source Kestra API Docs)[https://kestra.io/docs/api-reference/open-source]

**Clean up**

```bash
docker compose down
docker compose down -v
# optionally remove all stopped containers, networks, images, cache
docker system prune -a
docker system prune -v # and volumes
```

---

## Deployment

Deployed to an Oracle compute instance (GCP free tier insufficient for JVM). (Kestra docs for Google)[https://kestra.io/docs/installation/gcp-vm#create-a-vm-instance]

- Connect using SSH to install docker/docker compose.
- Create the default kestra docker-compose boilerplate from kestra

```bash
curl -o docker-compose.yml \
https://raw.githubusercontent.com/kestra-io/kestra/develop/docker-compose.yml
```

- Update authentication details for access the dashboard (email/password)
- Add base64 encoded credentials to .env_encoded and update reference in yaml
- Edit file to connect to GCS for kestra files (instead of local file system) (& restart docker, if necessary)
- In OCI dashboard, update firewall rules to enable access to VM on port 8080 and 8081 (monitoring) & update firewall in vm

IP: 147.224.210.83
PORT: 8080

TODO: deploy flows from Github workflow

### TODOs

- run on a schedule (kestra cron)
- set up Subflows or Flow Triggers to run all flows
- deploy from Github workflow
- monitoring / notifications
- update best track data if necessary (currently only adding rows if they don't exist (composite key))
  - don't add "provisional" data??
  - `TRACK_TYPE` column with `PROVISIONAL` OR `US-PROVISIONAL` should be updated in cochroach DB
  - other relevant columns:
    - `TRACK_TYPE` (other values): `MAIN` (reanalyzed, higher quality) or spur (short-lived, often alternate positions).
    - `USA_RECORD`: Contains 'P' to indicate a provisional minimum in central pressure, or other codes for preliminary, real-time data
- update hurricane website to display database last updated at
