#!/bin/bash
gcloud auth activate-service-account --key-file=/opt/keys/gcp-sa.json

gcloud secrets versions access latest \
  --secret=COCKROACH_CA> /app/certs/root.crt

chmod 600 /app/certs/root.crt

docker compose up -d