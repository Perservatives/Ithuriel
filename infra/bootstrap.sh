#!/usr/bin/env bash
# One-shot GCP bootstrap for Ithuriel.
#
# Usage:
#   ./infra/bootstrap.sh <project_id> [region]
#
# Expects:
#   - gcloud CLI installed and `gcloud auth login` already run
#   - terraform >= 1.7 installed (or run `brew install terraform`)
#   - billing account ID exported as $BILLING_ACCOUNT (or linked in console)
#
# What it does:
#   1. Sets the active gcloud project.
#   2. Enables the APIs Terraform needs (idempotent).
#   3. Creates an Artifact Registry repo for the API image (idempotent).
#   4. Renders terraform.tfvars from defaults + project id.
#   5. Runs `terraform init` and `terraform apply` from infra/terraform/.
#
# Anything that can't be automated (OAuth client creation, billing link)
# prints a clear "do this yourself" message.

set -euo pipefail

PROJECT_ID="${1:-}"
REGION="${2:-us-central1}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project_id> [region]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

if ! command -v gcloud >/dev/null; then
  echo "gcloud CLI not installed. Install with: brew install --cask google-cloud-sdk" >&2
  exit 1
fi

if ! command -v terraform >/dev/null; then
  echo "terraform not installed. Install with: brew install terraform" >&2
  exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q '@'; then
  echo "No active gcloud auth. Run: gcloud auth login && gcloud auth application-default login" >&2
  exit 1
fi

echo "→ Setting active project to $PROJECT_ID"
gcloud config set project "$PROJECT_ID" >/dev/null

if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  echo "→ Linking billing account $BILLING_ACCOUNT"
  gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" || true
else
  echo "⚠ BILLING_ACCOUNT not set. Make sure $PROJECT_ID has billing enabled in the console."
fi

echo "→ Enabling required APIs (this can take a minute)"
gcloud services enable \
  firestore.googleapis.com firebase.googleapis.com identitytoolkit.googleapis.com \
  pubsub.googleapis.com storage.googleapis.com run.googleapis.com \
  cloudfunctions.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com aiplatform.googleapis.com generativelanguage.googleapis.com \
  logging.googleapis.com monitoring.googleapis.com eventarc.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID"

echo "→ Creating Artifact Registry repo (idempotent)"
gcloud artifacts repositories create ithuriel \
  --repository-format=docker --location="$REGION" --project="$PROJECT_ID" \
  2>/dev/null || echo "  (already exists)"

API_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/api:latest"

TFVARS=infra/terraform/terraform.tfvars
if [[ ! -f "$TFVARS" ]]; then
  echo "→ Writing $TFVARS"
  cat > "$TFVARS" <<EOF
project_id          = "$PROJECT_ID"
region              = "$REGION"
api_image           = "$API_IMAGE"
oauth_client_id     = "${OAUTH_CLIENT_ID:-REPLACE.apps.googleusercontent.com}"
oauth_client_secret = "${OAUTH_CLIENT_SECRET:-REPLACE}"
allowed_origins     = ["https://ithuriel.dev", "http://localhost:5173"]
EOF
  echo "  (edit oauth_client_id / oauth_client_secret before apply if you want Google sign-in)"
fi

echo "→ terraform init"
(cd infra/terraform && terraform init -upgrade)

echo "→ terraform apply (review the plan, then type 'yes')"
(cd infra/terraform && terraform apply)

echo
echo "✓ Done. Useful outputs:"
(cd infra/terraform && terraform output)
