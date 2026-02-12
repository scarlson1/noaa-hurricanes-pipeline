#!/bin/bash
set -e

# Paths
ENV_FILE=/home/opc/app/.env_encoded
GCLOUD=/home/opc/google-cloud-sdk/bin/gcloud
PROJECT=historical-paths

# Ensure clean env file
rm -f "$ENV_FILE"

# Fetch GCP service account key and encode
GCP_SERVICE_ACCOUNT_B64=$($GCLOUD secrets versions access latest \
  --secret=NOAA_SERVICE_ACCOUNT --project=$PROJECT | base64 -w 0)
echo "SECRET_GCP_SERVICE_ACCOUNT=$GCP_SERVICE_ACCOUNT_B64" >> "$ENV_FILE"

# Fetch CockroachDB password and encode
COCKROACH_PASSWORD_B64=$($GCLOUD secrets versions access latest \
  --secret=DB_PASSWORD --project=$PROJECT | base64 -w 0)
echo "SECRET_COCKROACH_PASSWORD=$COCKROACH_PASSWORD_B64" >> "$ENV_FILE"

SLACK_URL_B64=$($GCLOUD secrets versions access latest \
  --secret=SLACK_WEBHOOK_URL --project=$PROJECT | base64 -w 0)
echo "SECRET_SLACK_WEBHOOK_URL=$SLACK_URL_B64" >> "$ENV_FILE"

# Optional: other secrets
# OTHER_SECRET_B64=$($GCLOUD secrets versions access latest --secret=other-secret --project=$PROJECT | base64 -w 0)
# echo "KESTRA_OTHER_SECRET_B64=$OTHER_SECRET_B64" >> "$ENV_FILE"

# Secure the file
chmod 600 "$ENV_FILE"
chown opc:opc "$ENV_FILE"

echo ".env_encoded file generated at $ENV_FILE"