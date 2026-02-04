NOAA Best Track Data --> BigQuery

---
[Encode service account](https://kestra.io/docs/how-to-guides/google-credentials):

```bash
echo SECRET_GCP_SERVICE_ACCOUNT=$(cat service-account.json | base64 -w 0) >> .env_encoded
```

[Encoding .env secrets](https://kestra.io/docs/concepts/secret)

```bash
while IFS='=' read -r key value; do
    echo "SECRET_$key=$(echo -n "$value" | base64)";
done < .env > .env_encoded
```

Combined:

```bash
: > .env_encoded

echo "SECRET_GCP_SERVICE_ACCOUNT=$(base64 < service-account.json | tr -d '\n')" >> .env_encoded

tr -d '\r' < .env | while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  echo "SECRET_$key=$(printf '%s' "$value" | base64 | tr -d '\n')" >> .env_encoded
done
```

Then update docker compose:

```yaml
  kestra:
    image: kestra/kestra:latest
    env_file:
      - .env_encoded
```

Load flows:

```bash
curl -X POST -u 'admin@kestra.io:Admin1234!' http://localhost:8080/api/v1/flows/import -F fileUpload=@flows/09_gcp_taxi_scheduled.yaml
```

Import into cockroachdb (need new approach: doesn't allow for filtering existing rows):

```bash
IMPORT INTO public.hurricane_data 
  (name,sid,basin,season,iso_time,usa_sshs,nature,latitude,longitude,usa_status,timestamp,unique_row_id) 
  CSV DATA ('gs://hurricanes-export/test.csv?AUTH=specified&CREDENTIALS={.BASE 64 ENCODED SERVICE ACCOUNT }) 
  WITH skip ‘1’;
```