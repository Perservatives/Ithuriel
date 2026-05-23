#!/usr/bin/env bash
# Push the user's API keys into GCP Secret Manager on synthesis-hack26svl-121.
#
# Usage:
#   ./scripts/push-keys-to-gcp.sh                  # interactive prompts
#   GEMINI_KEY=AIza… OPENAI_KEY=sk-… ./scripts/push-keys-to-gcp.sh
#
# Both keys are stored under stable secret names so the macOS app can
# resolve them at runtime via Secret Manager:
#   ithuriel-gemini-key
#   ithuriel-openai-key
#
# Idempotent: creates the secret if missing, otherwise adds a new version.

set -euo pipefail

PROJECT="${ITHURIEL_PROJECT:-synthesis-hack26svl-121}"

if ! command -v gcloud >/dev/null; then
  echo "gcloud CLI required. Install with: brew install --cask google-cloud-sdk" >&2
  exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q '@'; then
  echo "Not authenticated. Run: gcloud auth login" >&2
  exit 1
fi

GEMINI_KEY="${GEMINI_KEY:-}"
OPENAI_KEY="${OPENAI_KEY:-}"

if [[ -z "$GEMINI_KEY" ]]; then
  echo -n "Gemini API key (AIza…, leave blank to skip): "
  read -rs GEMINI_KEY; echo
fi
if [[ -z "$OPENAI_KEY" ]]; then
  echo -n "OpenAI API key (sk-…, leave blank to skip): "
  read -rs OPENAI_KEY; echo
fi

if [[ -z "$GEMINI_KEY" && -z "$OPENAI_KEY" ]]; then
  echo "Nothing to push." >&2
  exit 0
fi

gcloud services enable secretmanager.googleapis.com --project="$PROJECT" >/dev/null

upsert() {
  local name="$1" value="$2"
  [[ -z "$value" ]] && return 0
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "  $name: adding new version"
  else
    echo "  $name: creating"
    gcloud secrets create "$name" --replication-policy=automatic --project="$PROJECT" >/dev/null
  fi
  echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --project="$PROJECT" >/dev/null
}

upsert ithuriel-gemini-key "$GEMINI_KEY"
upsert ithuriel-openai-key "$OPENAI_KEY"

echo
echo "✓ Stored under project $PROJECT:"
gcloud secrets list --project="$PROJECT" --filter="name~ithuriel-" --format="value(name)"
echo
echo "The macOS app reads these on first launch via SecretManagerClient."
echo "Sign in with Google in Settings → Integrations to enable cloud resolution."
