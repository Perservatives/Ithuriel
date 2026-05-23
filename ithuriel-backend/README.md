# Ithuriel Backend

Google Cloud backend for **Ithuriel** — receives macOS context snapshots, processes them with Vertex AI, stores results in Firestore/GCS, and serves formatted context to AI tools in real time.

## Structure

| Path | Description |
|------|-------------|
| `api/` | Cloud Run — Node.js 20 + Fastify 4 + TypeScript |
| `processor/` | Cloud Functions Gen2 — Python 3.12 + Vertex AI |
| `terraform/` | Infrastructure (dev/prod state via GCS backend) |

## Local development

```bash
cd ithuriel-backend
docker compose up firestore pubsub pubsub-init

# API (hot reload)
docker compose --profile dev up api-dev
```

Set `FIREBASE_AUTH_EMULATOR_HOST` when using the Firebase Auth emulator. For production tokens, provide a service account via `GOOGLE_APPLICATION_CREDENTIALS`.

### API endpoints

| Method | Path | Auth |
|--------|------|------|
| GET | `/v1/health` | No |
| POST | `/v1/context/snapshot` | Bearer JWT |
| GET | `/v1/context/current?format=claude\|cursor\|chatgpt\|copilot` | Bearer JWT |
| GET | `/v1/context/history` | Bearer JWT |
| GET | `/v1/context/:id` | Bearer JWT |
| POST | `/v1/context/inject` | Bearer JWT |
| WS | `/v1/context/stream?token=<jwt>` | Query token |
| POST | `/v1/team/broadcast` | Bearer JWT |

All responses include `x-request-id` for tracing.

## Deploy

```bash
# Terraform (per environment)
cd terraform
terraform init -backend-config=environments/dev.backend.hcl
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Upload `processor.zip` to the configured GCS bucket before applying the functions module.

## Firestore indexes

Create a composite index on `users/{uid}/snapshots`:

- `status` ASC, `capturedAt` DESC

```bash
gcloud firestore indexes composite create \
  --collection-group=snapshots \
  --field-config=field-path=status,order=ascending \
  --field-config=field-path=capturedAt,order=descending
```
