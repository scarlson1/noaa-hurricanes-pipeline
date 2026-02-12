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
- Configure `docker-compose.yaml`:
  - Option 1: copy from `docker-compose-oracle.yaml`
  - Option2: create the default kestra docker-compose boilerplate from kestra

```bash
curl -o docker-compose.yml \
https://raw.githubusercontent.com/kestra-io/kestra/develop/docker-compose.yml
```

- Update authentication details for access the dashboard (email/password)
- Add base64 encoded credentials to .env_encoded and update reference in yaml
- add cockroach certs & map directory to container
- Edit file to connect to GCS for kestra files (instead of local file system) (& restart docker, if necessary)
- In OCI dashboard, update firewall rules to enable access to VM on port 8080 and 8081 (monitoring) & update firewall in vm

### Secrets

Copy service account into /app/service-account.json (for gcloud cli auth)

The following secrets are stored in GCP Secret Manager:

- `NOAA_SERVICE_ACCOUNT` - service account with BigQuery, GCS, Storage permissions
- `DB_PASSWORD` - Cockroach DB password
- `SLACK_WEBHOOK_URL` - slack url for notifications

**Manual option:**

- create .env_encoded
- copy over base64 encoded secrets
- secrets must be prepended with `SECRET_`

**Script:**

```bash
#!/bin/bash
set -e

# Paths
ENV_FILE=/home/opc/app/.env_encoded
GCLOUD=/home/opc/google-cloud-sdk/bin/gcloud
PROJECT=historical-paths

# Ensure clean env file
rm -f "$ENV_FILE"

# Fetch GCP service account key and encode
SERVICE_ACCOUNT_B64=$($GCLOUD secrets versions access latest \
  --secret=NOAA_SERVICE_ACCOUNT --project=$PROJECT | base64 -w 0)
echo "SECRET_GCP_SERVICE_ACCOUNT=$SERVICE_ACCOUNT_B64" >> "$ENV_FILE"

# Fetch CockroachDB password and encode
COCKROACH_PASSWORD_B64=$($GCLOUD secrets versions access latest \
  --secret=DB_PASSWORD --project=$PROJECT | base64 -w 0)
echo "SECRET_COCKROACH_PASSWORD=$COCKROACH_PASSWORD_B64" >> "$ENV_FILE"

# Optional: other secrets
# OTHER_SECRET_B64=$($GCLOUD secrets versions access latest --secret=other-secret --project=$PROJECT | base64 -w 0)
# echo "KESTRA_OTHER_SECRET_B64=$OTHER_SECRET_B64" >> "$ENV_FILE"

# Secure the file
chmod 600 "$ENV_FILE"
chown opc:opc "$ENV_FILE"

echo ".env_encoded file generated at $ENV_FILE"

```

Can also be added to `start.sh` script as well

### Cockroach DB CA

Install gcloud CLI on VM

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

Set permissions for SA:

```bash
chmod 600 /home/opc/app/service-account.json
```

Activate gcloud with service account:

```bash
gcloud config set project historical-paths
gcloud auth activate-service-account \
  --key-file=/home/opc/app/service-account.json
```

### Fetch secret & save to file

### Option 1: manually fetch with CLI & run

```bash
gcloud secrets versions access latest \
  --secret=COCKROACH_CA > /app/certs/root.crt
```

Ensure directory is mounted as volume to kestra container (`docker-compose.yaml`)

```yaml
volumes:
  - ./certs:/app/certs:ro
```

```bash
docker compose up -d
```

### Option 2: run as start up script

create: `/opt/kestra/start.sh` (systemd scripts won't run in user directory):

```bash
#!/bin/bash
set -e

GCLOUD=/home/opc/google-cloud-sdk/bin/gcloud
DOCKER=/usr/bin/docker
KEYFILE=/home/opc/app/service-account.json
PROJECT_ID=historical-paths
CERTFILE=/home/opc/app/certs/root.crt

echo "setting gcloud project"
$GCLOUD config set project $PROJECT_ID
sudo -u opc $GCLOUD config set project $PROJECT_ID

echo "Authenticating to GCP..."
$GCLOUD auth activate-service-account \
  --key-file=$KEYFILE

echo "Fetching Cockroach CA..."
rm -f $CERTFILE
$GCLOUD secrets versions access latest \
  --secret=COCKROACH_CA > $CERTFILE

chmod 600 $CERTFILE
# chown root:root /home/opc/app/certs/root.crt

# OPTIONALLY ADD ENV VARS FROM GCLOUD
ENV_FILE=/home/opc/app/.env_encoded

# Fetch CockroachDB password and encode
COCKROACH_PASSWORD_B64=$($GCLOUD secrets versions access latest \
  --secret=DB_PASSWORD --project=$PROJECT_ID | base64 -w 0)
echo "SECRET_COCKROACH_PASSWORD=$COCKROACH_PASSWORD_B64" >> "$ENV_FILE"

SLACK_URL_B64=$($GCLOUD secrets versions access latest \
  --secret=SLACK_WEBHOOK_URL --project=$PROJECT_ID | base64 -w 0)
echo "SECRET_SLACK_WEBHOOK_URL=$SLACK_URL_B64" >> "$ENV_FILE"

# used in docker-compose.yaml (not as kestra secret)
GEMINI_KEY_B64=$($GCLOUD secrets versions access latest \
  --secret=GEMINI_KEY --project=$PROJECT_ID | base64 -w 0)
echo "GEMINI_KEY=$GEMINI_KEY_B64" >> "$ENV_FILE"

# Secure the file
chmod 600 "$ENV_FILE"
chown opc:opc "$ENV_FILE"

echo ".env_encoded file generated at $ENV_FILE"

echo "Starting Docker Compose..."
cd /home/opc/app
$DOCKER compose up -d

echo "Startup complete."
```

Make it executable

```bash
chmod +x /opt/kestra/start.sh
sudo chmod 755 /opt/kestra/start.sh
# if SELinux context enforcing:
sudo chcon -t bin_t /opt/kestra/start.sh
```

**Create systemd Service**

systemd service to start automatically on boot:

create `/etc/systemd/system/kestra.service`

Put this inside:

```ini
[Unit]
Description=Kestra Startup Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
User=opc
ExecStart=/opt/kestra/start.sh
RemainAfterExit=true
Environment="HOME=/home/opc"

[Install]
WantedBy=multi-user.target
```

Tell SELinux that it is an executable script:

```bash
sudo chcon -t bin_t /opt/kestra/start.sh
sudo chown root:root /opt/kestra/start.sh
sudo chmod 755 /opt/kestra/start.sh
# chcon is temporary; after a relabel or restorecon, it may revert. For permanent fix:
sudo semanage fcontext -a -t bin_t "/opt/kestra/start.sh"
sudo restorecon -v /opt/kestra/start.sh

# ensure key is readable by otc
chmod 600 /home/opc/app/service-account.json
chown opc:opc /home/opc/app/service-account.json

# deal with SELinux type
sudo semanage fcontext -a -t bin_t "/home/opc/app/service-account.json"
sudo restorecon -v /home/opc/app/service-account.json
```

**Enable it**

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable service:

```bash
sudo systemctl enable kestra.service
# Created symlink /etc/systemd/system/multi-user.target.wants/kestra.service → /etc/systemd/system/kestra.service.
```

start it (without reboot):

```bash
sudo systemctl start kestra.service
```

check logs:

```bash
sudo journalctl -u kestra.service -f
sudo systemctl status kestra.service
```

Ensure docker automatically starts on reboot:

```bash
sudo systemctl enable docker.service
```

**Connect to UI:**

IP: 147.224.210.83
PORT: 8080

TODO: deploy flows from Github workflow

### TODOs

- update schedule (kestra cron) to filter down to month instead of year (filter on iso_time instead of year)
- deploy Kestra flows from Github workflow
- monitoring / notifications
- update best track data if necessary (currently only adding rows if they don't exist (composite key))
  - don't add "provisional" data??
  - `TRACK_TYPE` column with `PROVISIONAL` OR `US-PROVISIONAL` should be updated in cochroach DB
  - other relevant columns:
    - `TRACK_TYPE` (other values): `MAIN` (reanalyzed, higher quality) or spur (short-lived, often alternate positions).
    - `USA_RECORD`: Contains 'P' to indicate a provisional minimum in central pressure, or other codes for preliminary, real-time data
- update hurricane website to display database last updated at
