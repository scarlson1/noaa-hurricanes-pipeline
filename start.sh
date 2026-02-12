#!/bin/bash
set -e

GCLOUD=/home/opc/google-cloud-sdk/bin/gcloud
DOCKER=/usr/bin/docker
KEYFILE=/home/opc/app/service-account.json
PROJECT_ID=historical-paths
CERTFILE=/home/opc/app/certs/root.crt
ENV_FILE=/home/opc/app/.env_encoded

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

# LOAD SECRETS FROM SECRET MANAGER

# Ensure clean env file
rm -f "$ENV_FILE"

# Fetch GCP service account key and encode
GCP_SERVICE_ACCOUNT_B64=$($GCLOUD secrets versions access latest \
  --secret=NOAA_SERVICE_ACCOUNT --project=$PROJECT_ID | base64 -w 0)
echo "SECRET_GCP_SERVICE_ACCOUNT=$GCP_SERVICE_ACCOUNT_B64" >> "$ENV_FILE"

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