# Deploying Ithuriel to GCP

End-to-end bootstrap for a fresh Google Cloud project. Run from the repo root.

## Prerequisites

- `gcloud` (authenticated, billing-enabled project)
- `terraform` ≥ 1.7
- `node` ≥ 20 and `npm`
- A Google Cloud project (referred to below as `$PROJECT_ID`)

## 1. Enable foundations

```bash
export PROJECT_ID=synthesis-hack26svl-121   # Synthesis Hackathon-121
export REGION=us-central1
gcloud config set project "$PROJECT_ID"

# One-time: create Firebase + identity toolkit on top of the GCP project.
gcloud services enable firebase.googleapis.com identitytoolkit.googleapis.com
gcloud firebase projects:addfirebase "$PROJECT_ID" || true
```

In the [Firebase console](https://console.firebase.google.com/) for the
project:

- Enable **Authentication → Sign-in method → Google**.
- Note the **Web API key** (Project settings → General). Drop it into the
  macOS app's Settings → Integrations as `Firebase web API key`.

Create an OAuth 2.0 client (APIs & Services → Credentials → OAuth client ID
→ Web application). Authorized redirect URI:

```
https://<your cloud-run hostname>/auth/callback
```

(Run Terraform first to get the hostname, then come back and add it.)

## 2. Build & push the API container

```bash
cd services/api
npm install
gcloud auth configure-docker $REGION-docker.pkg.dev

# Create Artifact Registry first time (skip if Terraform already created it)
gcloud artifacts repositories create ithuriel \
  --location=$REGION --repository-format=docker || true

docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/api:latest .
docker push     $REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/api:latest
cd ../..
```

## 3. Apply Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in: project_id, oauth_client_id, oauth_client_secret, api_image.
terraform init
terraform apply
cd ../..
```

`terraform output api_url` gives you the public Cloud Run hostname. Plug
that into the OAuth client's authorized redirect URI (step 1) **and** the
macOS app's Settings → Integrations → Cloud Run base URL.

## 4. Deploy Firestore + Storage rules

```bash
cd infra
npx -y firebase-tools deploy --project "$PROJECT_ID" \
  --only firestore:rules,firestore:indexes,storage:rules \
  --non-interactive
cd ..
```

## 5. Deploy the Cloud Function

```bash
gcloud functions deploy ithuriel-processor \
  --gen2 \
  --runtime=python312 \
  --region=$REGION \
  --source=services/functions/processor \
  --entry-point=handle \
  --trigger-topic=ithuriel-snapshots \
  --service-account=ithuriel-processor@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,VERTEX_REGION=$REGION,GCS_BUCKET_SNAPSHOTS=$PROJECT_ID-ithuriel-snapshots,PROCESSED_TOPIC=ithuriel-snapshots-processed
```

## 6. Wire up Cloud Build (optional, for CI)

```bash
gcloud builds triggers create github \
  --repo-name=Ithuriel \
  --repo-owner=Perservatives \
  --branch-pattern=^main$ \
  --build-config=infra/cloudbuild.yaml
```

## 7. Smoke test

```bash
API_URL=$(cd infra/terraform && terraform output -raw api_url)
curl "$API_URL/health"
# → {"status":"ok","ts":"..."}
```

## 8. macOS app sign-in

1. Launch the Ithuriel menu bar app.
2. Settings → Integrations → paste Cloud Run base URL + Firebase web API key.
3. Click "Sign in with Google" — the default browser opens, auth happens,
   the browser bounces to `ithuriel://auth/callback?token=…`, the agent
   exchanges the custom token for an ID token, and you're signed in.
4. Settings → Agent → paste your Gemini API key. You're done.

## Architecture recap

```
macOS agent ──POST /v1/context/snapshot──► Cloud Run API
                                              │
                                              ├──► Firestore snapshots/{id}
                                              ├──► GCS (raw JSON blob)
                                              └──► Pub/Sub ithuriel-snapshots
                                                          │
                                                          ▼
                                                  Cloud Function (Python)
                                                   ├── Vertex AI summarize
                                                   ├── Vertex AI embeddings
                                                   └── Firestore (back-fill)

macOS agent ──POST /v1/agent/run────────────► Cloud Run API ──► Firestore agentRuns/{id}
```
