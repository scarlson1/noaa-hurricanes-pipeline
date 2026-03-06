# Hurricanes Pipeline — Deployment & Infrastructure Guide

> Oracle Cloud VM · Terraform · Kestra · Google Cloud Platform

---

## 1. Overview

This document covers the complete setup and ongoing deployment of the Hurricanes Pipeline — a Kestra-based workflow engine running on Oracle Cloud Infrastructure (OCI), with Google Cloud Storage (GCS) and BigQuery as the data backend.

### Architecture Summary

| Component       | Details                                                            |
| --------------- | ------------------------------------------------------------------ |
| OCI VM          | VM.Standard.A1.Flex — 1 OCPU, 6 GB RAM — Oracle Linux              |
| Kestra          | v1.3 — Docker Compose — standalone mode with Postgres backend      |
| GCS Bucket      | `hurricanes_pipeline_kestra` — US multi-region                     |
| BigQuery        | `historical-paths` project — `hurricane_data` dataset              |
| CockroachDB     | `idemand-db-cluster-14272.5xj.gcp-us-central1.cockroachlabs.cloud` |
| Terraform State | `hurricanes_pipeline_tf_state` GCS bucket                          |
| CI/CD           | GitHub Actions — auto-deploys flows and infrastructure             |

---

## 2. Prerequisites

### Required Tools

- Terraform >= 1.5
- OCI CLI — configured with `~/.oci/oci_api_key.pem`
- gcloud CLI — authenticated to the `historical-paths` project
- SSH key pair — `~/.ssh/oracle-kestra` and `~/.ssh/oracle-kestra.pub`

### Verify Installations

```bash
terraform -version
oci --version
gcloud --version
ls ~/.ssh/oracle-kestra*
```

### OCI API Key Setup

If the OCI API key is not yet configured, generate it in the OCI console under **Identity → Users → Your User → API Keys**, then place the downloaded `.pem` at:

```
~/.oci/oci_api_key.pem
```

---

## 3. Terraform Setup

Terraform manages the OCI VM, VCN, networking, GCS bucket, BigQuery dataset, and the Kestra GCP service account. State is stored remotely in GCS.

### 3.1 File Structure

```
terraform/
├── providers.tf          # Provider config + GCS backend
├── main.tf               # Module wiring
├── variables.tf          # Variable declarations
├── outputs.tf            # Exposes kestra_sa_key
├── terraform.tfvars      # Secret values — gitignored
└── modules/
    ├── oci/
    │   ├── main.tf       # VM, VCN, subnet, security list
    │   └── variables.tf
    └── gcp/
        ├── main.tf       # GCS, BQ, service account, IAM
        └── variables.tf
```

### 3.2 terraform.tfvars

This file contains all secret values and is gitignored. It must be created manually on any new machine. **Never commit this file.**

```hcl
# OCI
oci_tenancy_ocid        = "ocid1.tenancy.oc1..xxx"
oci_user_ocid           = "ocid1.user.oc1..xxx"
oci_fingerprint         = "aa:bb:cc:..."
oci_private_key_path    = "~/.oci/oci_api_key.pem"
oci_region              = "us-chicago-1"
oci_compartment_ocid    = "ocid1.tenancy.oc1..xxx"  # same as tenancy for free tier
oci_availability_domain = "kWVD:US-CHICAGO-1-AD-1"
oci_vm_image_ocid       = "ocid1.image.oc1..xxx"

# GCP
gcp_project             = "historical-paths"
gcp_region              = "us-central1"
gcp_credentials_file    = "~/.gcp/service-account.json"
gcs_bucket_name         = "hurricanes_pipeline_kestra"
bq_dataset_id           = "hurricane_data"
```

> **Note:** Retrieve OCI values with `oci iam availability-domain list` and `oci compute instance list`

### 3.3 First-Time Initialization

Create the Terraform state bucket before running init (only needed once):

```bash
gsutil mb -l us-central1 gs://hurricanes_pipeline_tf_state
gsutil versioning set on gs://hurricanes_pipeline_tf_state
```

Then initialize Terraform:

```bash
cd terraform/
terraform init
```

### 3.4 Importing Existing Resources

Since the VM, GCS bucket, and BigQuery dataset were created before Terraform, they must be imported into state before the first apply. Run these once:

```bash
# OCI instance
terraform import module.oci.oci_core_instance.kestra_vm <instance-ocid>

# OCI VCN
terraform import module.oci.oci_core_vcn.kestra_vcn <vcn-ocid>

# OCI subnet
terraform import module.oci.oci_core_subnet.kestra_subnet <subnet-ocid>

# GCS bucket
terraform import module.gcp.google_storage_bucket.kestra_bucket hurricanes_pipeline_kestra

# BigQuery dataset
terraform import module.gcp.google_bigquery_dataset.kestra_dataset historical-paths/hurricane_data
```

Get OCI resource OCIDs using the CLI:

```bash
# List all instances
oci compute instance list --compartment-id <tenancy-ocid> \
  --query 'data[].{"name":"display-name","ocid":"id"}' --output table

# List all VCNs
oci network vcn list --compartment-id <tenancy-ocid> \
  --query 'data[].{"name":"display-name","ocid":"id"}' --output table

# List all subnets
oci network subnet list --compartment-id <tenancy-ocid> \
  --query 'data[].{"name":"display-name","ocid":"id"}' --output table
```

> ⚠️ **Warning:** Always verify OCIDs match the kestra resources, not the orderbook-pipeline resources.

### 3.5 Plan and Apply

After importing, review the plan carefully before applying:

```bash
terraform plan
```

What to look for in the plan:

- `~` — in-place update, safe to apply
- `-/+` — destroy and recreate, **stop and investigate** — especially for GCS bucket or BQ dataset
- `+` — new resource, safe for IAM/service account resources

```bash
terraform apply
```

### 3.6 Retrieving the Service Account Key

After apply, export the Terraform-generated GCP service account key for use in Kestra:

```bash
terraform output -raw kestra_sa_key | base64 -d > ../kestra-sa.json
```

> **Note:** This key belongs to `kestra-sa@historical-paths.iam.gserviceaccount.com` with scoped GCS and BigQuery permissions only.

### 3.7 GCP Permissions Required for Terraform

The service account in `gcp_credentials_file` must have the following roles:

- `roles/iam.serviceAccountAdmin`
- `roles/iam.serviceAccountKeyAdmin`
- `roles/resourcemanager.projectIamAdmin`
- `roles/storage.admin`
- `roles/bigquery.admin`

Grant missing roles with:

```bash
SA=$(cat ~/.gcp/service-account.json | python3 -c "import sys,json; print(json.load(sys.stdin)['client_email'])")
gcloud projects add-iam-policy-binding historical-paths \
  --member="serviceAccount:$SA" \
  --role="roles/iam.serviceAccountKeyAdmin"
```

---

## 4. VM Setup (One-Time)

These steps are performed once on the OCI VM to install the systemd service. After this, all deployments are handled automatically by GitHub Actions.

### 4.1 SSH Access

```bash
ssh -i ~/.ssh/oracle-kestra opc@147.224.210.83
```

Or using the SSH config alias:

```bash
ssh hurricanes_pipeline
```

Correct `~/.ssh/config` entry:

```
Host hurricanes_pipeline
  HostName 147.224.210.83
  User opc
  IdentityFile ~/.ssh/oracle-kestra
  AddKeysToAgent yes
```

### 4.2 Install systemd Service

Run these commands on the VM to register Kestra as a system service that starts automatically on boot:

```bash
# Create the kestra working directory
mkdir -p ~/kestra/certs

# Write the systemd service file
sudo tee /etc/systemd/system/kestra.service > /dev/null <<'EOF'
[Unit]
Description=Kestra Workflow Engine
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=opc
WorkingDirectory=/home/opc/kestra
ExecStart=/usr/bin/docker compose -f compose.yaml up
ExecStop=/usr/bin/docker compose -f compose.yaml down
Restart=always
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

# Register and enable
sudo systemctl daemon-reload
sudo systemctl enable kestra
```

> **Note:** `systemctl enable` registers the service to start on boot. It does not start it immediately.

### 4.3 First Deploy — Copy Files Manually

Before Kestra can start, the required files must exist on the VM. On first setup, copy them manually from your local machine:

(also copied over in github workflow)

```bash
VM="opc@147.224.210.83"
OPTS="-i ~/.ssh/oracle-kestra"

scp $OPTS docker-compose-oracle.yaml  $VM:~/kestra/compose.yaml
scp $OPTS kestra-sa.json              $VM:~/kestra/service-account.json
scp $OPTS path/to/root.crt            $VM:~/kestra/certs/root.crt
scp $OPTS .env                         $VM:~/kestra/.env
scp $OPTS .env_encoded                $VM:~/kestra/.env_encoded
```

### 4.4 Start Kestra

```bash
sudo systemctl start kestra

# Monitor startup logs
sudo journalctl -u kestra -f
```

Kestra is ready when logs show it listening on port 8080. The UI is then accessible at:

```
http://147.224.210.83:8080
```

### 4.5 Useful systemd Commands

```bash
sudo systemctl status kestra      # current status
sudo systemctl restart kestra     # restart
sudo systemctl stop kestra        # stop
sudo journalctl -u kestra -n 100  # last 100 log lines
sudo journalctl -u kestra -f      # follow live logs
```

---

## 5. Environment Files

Kestra uses two separate env files for different purposes. Both must be present in `~/kestra/` on the VM.

### 5.1 `.env` — Docker Compose Variables

Plain `key=value` pairs read by Docker Compose for `${VAR}` interpolation in `docker-compose-oracle.yaml`. **Not** base64 encoded.

```bash
POSTGRES_PASSWORD=<strong-password>
KESTRA_USER=spencercarlson@mac.com
KESTRA_PASSWORD=<kestra-ui-password>
GEMINI_KEY=<gemini-api-key>
```

### 5.2 `.env_encoded` — Kestra Secret Store

Base64-encoded values prefixed with `SECRET_`. Loaded into Kestra's internal secret store and accessed within flows using `{{ secret('KEY') }}`.

```bash
SECRET_GCP_SERVICE_ACCOUNT=<base64-encoded-json>
SECRET_COCKROACH_PASSWORD=<base64-encoded-value>
SECRET_SLACK_WEBHOOK_URL=<base64-encoded-url>
```

To manually encode a value:

```bash
echo -n "your-secret-value" | base64 -w 0
```

To reference a secret inside a flow:

```yaml
password: "{{ secret('COCKROACH_PASSWORD') }}"
url: "{{ secret('SLACK_WEBHOOK_URL') }}"
```

### 5.3 `service-account.json`

The GCP service account JSON key mounted into the Kestra container at `/.gcp/credentials.json`. Used by `GOOGLE_APPLICATION_CREDENTIALS` for GCS storage backend access. This is the `kestra-sa` Terraform-managed key, retrieved after `terraform apply`:

```bash
terraform output -raw kestra_sa_key | base64 -d > kestra-sa.json
```

---

## 6. GitHub Actions

Two workflows handle ongoing deployments automatically on push to `main`.

### 6.1 `deploy_infra.yml` — Infrastructure Deploy

**Triggered by:** changes to `docker-compose-oracle.yaml`

What it does:

1. Writes SSH private key from secrets
2. Writes `service-account.json` from secrets
3. Generates `.env` with plain values for Docker Compose
4. Generates `.env_encoded` with base64 values for Kestra secret store
5. Writes CockroachDB `root.crt` from secrets (base64 decoded)
6. SCPs all files to `~/kestra/` on the VM
7. Runs `sudo systemctl restart kestra`

> **Note:** This workflow does not re-run if only flow files change. Use `deploy_flows.yml` for that.

### 6.2 `deploy_flows.yml` — Flow Deploy

**Triggered by:** any change under `flows/**`

Uses the official Kestra deploy action to push updated flows directly to the running Kestra instance via its API:

```yaml
- uses: kestra-io/deploy-action@master
  with:
    resource: flow
    namespace: hurricanes
    directory: ./flows
    server: http://${{ secrets.OCI_VM_IP }}:8080
    user: ${{ secrets.KESTRA_USER }}
    password: ${{ secrets.KESTRA_PASSWORD }}
```

### 6.3 Required GitHub Secrets

Set these under **Settings → Secrets and Variables → Actions**:

| Secret                     | Value / Source                                         |
| -------------------------- | ------------------------------------------------------ |
| `OCI_VM_IP`                | `147.224.210.83`                                       |
| `OCI_SSH_PRIVATE_KEY`      | Contents of `~/.ssh/oracle-kestra`                     |
| `GCP_SERVICE_ACCOUNT_JSON` | Contents of `kestra-sa.json` (from `terraform output`) |
| `KESTRA_USER`              | `spencercarlson@mac.com`                               |
| `KESTRA_PASSWORD`          | Kestra UI password                                     |
| `POSTGRES_PASSWORD`        | Postgres password for internal Kestra DB               |
| `GEMINI_KEY`               | Google Gemini API key                                  |
| `COCKROACH_PASSWORD`       | CockroachDB user password                              |
| `SLACK_WEBHOOK_URL`        | Slack incoming webhook URL                             |
| `COCKROACH_CA_CERT`        | base64-encoded contents of `root.crt`                  |

To get the base64-encoded CockroachDB cert:

```bash
cat path/to/root.crt | base64 | pbcopy   # copies to clipboard (macOS)
```

---

## 7. CockroachDB SSL Certificate

Kestra flows connect to CockroachDB using SSL with `sslmode=verify-full`. The root certificate must be present on the VM at `~/kestra/certs/root.crt`, which Docker Compose mounts into the container at `/app/certs/root.crt`.

### JDBC Connection String

```
jdbc:postgresql://idemand-db-cluster-14272.5xj.gcp-us-central1.cockroachlabs.cloud
  :26257/historical_paths
  ?sslmode=verify-full&sslrootcert=/app/certs/root.crt
```

### Certificate Deployment

The cert is stored as a base64-encoded GitHub secret (`COCKROACH_CA_CERT`) and decoded onto the VM by `deploy_infra.yml`:

```yaml
- name: Write CockroachDB cert
  run: echo '${{ secrets.COCKROACH_CA_CERT }}' | base64 -d > root.crt

- name: Copy files to VM
  run: scp $SCP_OPTS root.crt $VM:~/kestra/certs/root.crt
```

To update the cert, re-encode it, update the GitHub secret, and push a change to `docker-compose-oracle.yaml` to trigger a redeploy.

---

## 8. Ongoing Operations

### Deploying Flow Changes

Push changes to any file under `flows/` to `main`. The `deploy_flows.yml` workflow automatically pushes updated flows to Kestra within ~1 minute.

### Deploying Config Changes

Push changes to `docker-compose-oracle.yaml` to `main`. The `deploy_infra.yml` workflow regenerates env files, copies everything to the VM, and restarts Kestra.

### Updating Terraform Infrastructure

```bash
cd terraform/
terraform plan    # always review first
terraform apply
```

> ⚠️ **Warning:** If changing VM shape, stop the instance first:
>
> ```bash
> oci compute instance action --instance-id <ocid> --action STOP
> ```

### Rotating the GCP Service Account Key

```bash
cd terraform/
terraform apply -replace=module.gcp.google_service_account_key.kestra_key
terraform output -raw kestra_sa_key | base64 -d > ../kestra-sa.json
```

Then update the `GCP_SERVICE_ACCOUNT_JSON` GitHub secret and push to trigger a redeploy.

### Checking Service Health

```bash
# SSH in
ssh -i ~/.ssh/oracle-kestra opc@147.224.210.83

# Check service status
sudo systemctl status kestra

# View recent logs
sudo journalctl -u kestra -n 100

# Check containers are running
docker ps
```

---

## 9. .gitignore

The following are gitignored and must never be committed:

```gitignore
# Secrets & credentials
*.json                  # all JSON files including service accounts
.env
.env_encoded

# Terraform
terraform.tfvars        # OCI/GCP credentials
.terraform/             # downloaded provider binaries
.terraform.lock.hcl
*.tfstate
*.tfstate.backup
terraform.tfplan
```

---

## 10. Troubleshooting

### Kestra flow wget/network failures

Flows that make outbound network requests (e.g. `wget` to NOAA) may fail if OCI egress is blocked. The security list includes a rule allowing all egress (`protocol: all, destination: 0.0.0.0/0`). If flows still fail, verify the security list is attached to the subnet in the OCI console.

### SSH permission denied

Two common causes:

- Key filename mismatch — config references `oracle_kestra` (underscore) but the file is `oracle-kestra` (hyphen)
- Wrong IP — SSH config and actual VM IP must match

```bash
ssh -v -i ~/.ssh/oracle-kestra opc@147.224.210.83
```

### Terraform location forces replacement

GCS bucket and BigQuery dataset locations are immutable. If Terraform shows a `-/+` replacement for location changes, update the Terraform config to match the actual resource location rather than `var.gcp_region`:

```hcl
location = "US"   # not var.gcp_region
```

### Terraform 403 on GCP resources

The service account used by Terraform (`gcp_credentials_file`) needs IAM permissions. Grant missing roles with `gcloud projects add-iam-policy-binding`. See [Section 3.7](#37-gcp-permissions-required-for-terraform) for required roles.

### Kestra UI not accessible

Check in order:

1. VM is running: OCI console → Compute → Instances
2. Port 8080 allowed: OCI console → Networking → Security Lists → `kestra-security-list`
3. Service is up: `sudo systemctl status kestra`
4. Containers running: `docker ps`
5. No port conflict: `sudo ss -tlnp | grep 8080`

### `.env_encoded` not created on VM

The `deploy_infra.yml` workflow generates `.env_encoded` but must also SCP it to the VM. Verify the Copy files step includes:

```yaml
scp $SCP_OPTS .env_encoded $VM:~/kestra/.env_encoded
```

Add a verify step to confirm file generation before copy:

```yaml
- name: Verify generated files
  run: |
    echo '=== .env_encoded ===' && wc -l .env_encoded && head -c 50 .env_encoded
```
