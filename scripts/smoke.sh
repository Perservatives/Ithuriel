#!/usr/bin/env bash
# smoke.sh — CLI smoke test for the Ithuriel backend on GCP
# Usage: ./scripts/smoke.sh

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Counters ──────────────────────────────────────────────────────────────────
TOTAL=14
PASSED=0
FAILED=0

# ── Constants ─────────────────────────────────────────────────────────────────
GCP_PROJECT="synthesis-hack26svl-121"
REGION="us-central1"
API_URL="https://ithuriel-api-596592790807.us-central1.run.app"
MCP_URL="https://ithuriel-mcp-596592790807.us-central1.run.app"
GCS_BUCKET="gs://synthesis-hack26svl-121-ithuriel-snapshots"
FIREBASE_WEB_API_KEY="AIzaSyDMtG-Tuzq5l_2siR93ONT4hKvEQN5OgRc"
FUNCTION_NAME="ithuriel-processor"

# ── Helper: print test result ──────────────────────────────────────────────────
# pass_test <n> <label>
pass_test() {
  local n="$1" label="$2"
  printf "[%2s/%s] %-42s ${GREEN}✅${RESET}\n" "$n" "$TOTAL" "$label"
  PASSED=$((PASSED + 1))
}

# fail_test <n> <label> <reason>
fail_test() {
  local n="$1" label="$2" reason="$3"
  printf "[%2s/%s] %-42s ${RED}❌  %s${RESET}\n" "$n" "$TOTAL" "$label" "$reason"
  FAILED=$((FAILED + 1))
}

# ── Header ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Ithuriel Backend Smoke Test                              ${RESET}"
echo -e "${BOLD}  Project: ${GCP_PROJECT}${RESET}"
echo -e "${BOLD}  Region:  ${REGION}${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════
# [1/14] Tooling check
# ═══════════════════════════════════════════════════════════════
N=1
LABEL="tooling check (gcloud, curl, jq, python3)"
MISSING=""
for cmd in gcloud curl jq python3; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING="$MISSING $cmd"
  fi
done

if [[ -n "$MISSING" ]]; then
  fail_test "$N" "$LABEL" "missing:$MISSING"
else
  pass_test "$N" "$LABEL"
  echo "       gcloud  $(gcloud --version 2>/dev/null | head -1)"
  echo "       curl    $(curl --version | head -1)"
  echo "       jq      $(jq --version)"
  echo "       python3 $(python3 --version)"
fi

# ═══════════════════════════════════════════════════════════════
# [2/14] Auth check
# ═══════════════════════════════════════════════════════════════
N=2
LABEL="gcloud auth & project"
GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)

if [[ "$GCLOUD_PROJECT" != "$GCP_PROJECT" ]]; then
  fail_test "$N" "$LABEL" "project='$GCLOUD_PROJECT' (want '$GCP_PROJECT') → run: gcloud config set project $GCP_PROJECT"
elif [[ -z "$GCLOUD_ACCOUNT" ]]; then
  fail_test "$N" "$LABEL" "no account active → run: gcloud auth login"
else
  pass_test "$N" "$LABEL"
  echo "       account: $GCLOUD_ACCOUNT"
  echo "       project: $GCLOUD_PROJECT"
fi

# ═══════════════════════════════════════════════════════════════
# [3/14] API health
# ═══════════════════════════════════════════════════════════════
N=3
LABEL="api health (/health → 200 + status:ok)"
HTTP_CODE=$(curl -s -o /tmp/ithuriel_api_health.json -w "%{http_code}" "$API_URL/health" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "200" ]]; then
  fail_test "$N" "$LABEL" "HTTP $HTTP_CODE from $API_URL/health"
else
  STATUS=$(jq -r '.status // empty' /tmp/ithuriel_api_health.json 2>/dev/null || true)
  if [[ "$STATUS" != "ok" ]]; then
    fail_test "$N" "$LABEL" "HTTP 200 but status='$STATUS' (want 'ok') — body: $(cat /tmp/ithuriel_api_health.json)"
  else
    pass_test "$N" "$LABEL"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# [4/14] MCP health
# ═══════════════════════════════════════════════════════════════
N=4
LABEL="mcp health (/health → 200)"
HTTP_CODE=$(curl -s -o /tmp/ithuriel_mcp_health.json -w "%{http_code}" "$MCP_URL/health" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "200" ]]; then
  fail_test "$N" "$LABEL" "HTTP $HTTP_CODE from $MCP_URL/health"
else
  pass_test "$N" "$LABEL"
fi

# ═══════════════════════════════════════════════════════════════
# [5/14] MCP no-auth = 401
# ═══════════════════════════════════════════════════════════════
N=5
LABEL="mcp POST /mcp without bearer → 401"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$MCP_URL/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"smoke","version":"1"},"capabilities":{}}}' \
  2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "401" ]]; then
  pass_test "$N" "$LABEL"
else
  fail_test "$N" "$LABEL" "expected 401, got HTTP $HTTP_CODE"
fi

# ═══════════════════════════════════════════════════════════════
# [6/14] MCP initialize with dummy bearer
# ═══════════════════════════════════════════════════════════════
N=6
LABEL="mcp initialize (dummy-token) → protocolVersion + serverInfo"
# MCP server requires both application/json and text/event-stream in Accept
HTTP_CODE=$(curl -s -o /tmp/ithuriel_mcp_init.json -w "%{http_code}" \
  -X POST "$MCP_URL/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer dummy-token" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"smoke","version":"1"},"capabilities":{}}}' \
  2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]]; then
  fail_test "$N" "$LABEL" "HTTP $HTTP_CODE — body: $(cat /tmp/ithuriel_mcp_init.json 2>/dev/null)"
else
  PROTO=$(jq -r '.result.protocolVersion // empty' /tmp/ithuriel_mcp_init.json 2>/dev/null || true)
  SERVER_NAME=$(jq -r '.result.serverInfo.name // empty' /tmp/ithuriel_mcp_init.json 2>/dev/null || true)
  if [[ -z "$PROTO" ]]; then
    fail_test "$N" "$LABEL" "missing .result.protocolVersion — body: $(cat /tmp/ithuriel_mcp_init.json)"
  elif [[ "$SERVER_NAME" != "ithuriel" ]]; then
    fail_test "$N" "$LABEL" "serverInfo.name='$SERVER_NAME' (want 'ithuriel')"
  else
    pass_test "$N" "$LABEL"
    echo "       protocolVersion: $PROTO  serverInfo.name: $SERVER_NAME"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# [7/14] MCP tool list
# ═══════════════════════════════════════════════════════════════
N=7
LABEL="mcp tools/list → all 6 required tools present"
HTTP_CODE=$(curl -s -o /tmp/ithuriel_mcp_tools.json -w "%{http_code}" \
  -X POST "$MCP_URL/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer dummy-token" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  2>/dev/null || echo "000")

REQUIRED_TOOLS=(
  "get_current_context"
  "get_context_history"
  "get_snapshot"
  "format_context_for_tool"
  "list_agent_runs"
  "search_context"
)

if [[ "$HTTP_CODE" != "200" ]]; then
  fail_test "$N" "$LABEL" "HTTP $HTTP_CODE — body: $(cat /tmp/ithuriel_mcp_tools.json 2>/dev/null)"
else
  # Extract tool names from response
  TOOL_NAMES=$(jq -r '.result.tools[].name // empty' /tmp/ithuriel_mcp_tools.json 2>/dev/null || true)
  ALL_FOUND=true
  echo "       Tool list:"
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if echo "$TOOL_NAMES" | grep -qxF "$tool"; then
      printf "         %-38s ${GREEN}✅${RESET}\n" "$tool"
    else
      printf "         %-38s ${RED}❌${RESET}\n" "$tool"
      ALL_FOUND=false
    fi
  done
  if $ALL_FOUND; then
    pass_test "$N" "$LABEL"
  else
    fail_test "$N" "$LABEL" "one or more required tools missing from tools/list"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# [8/14] API /v1/context/current without auth = 401
# ═══════════════════════════════════════════════════════════════
N=8
LABEL="api GET /v1/context/current without auth → 401/403"
HTTP_CODE=$(curl -s -o /tmp/ithuriel_ctx_noauth.json -w "%{http_code}" \
  "$API_URL/v1/context/current" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
  pass_test "$N" "$LABEL"
else
  BODY=$(cat /tmp/ithuriel_ctx_noauth.json 2>/dev/null | head -c 200 || true)
  fail_test "$N" "$LABEL" "expected 401/403, got HTTP $HTTP_CODE — service bug: $BODY"
fi

# ═══════════════════════════════════════════════════════════════
# [9/14] Cloud Function deployed
# ═══════════════════════════════════════════════════════════════
N=9
LABEL="cloud function '$FUNCTION_NAME' ACTIVE + env vars"
# Use JSON format to avoid tab-ambiguity in value() output
FUNC_JSON=$(gcloud functions describe "$FUNCTION_NAME" \
  --region="$REGION" \
  --gen2 \
  --format=json \
  2>/dev/null || true)

FUNC_STATE=$(echo "$FUNC_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',''))" 2>/dev/null || true)
FUNC_ENV_KEYS=$(echo "$FUNC_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); envs=d.get('serviceConfig',{}).get('environmentVariables',{}); print('\n'.join(envs.keys()))" 2>/dev/null || true)

REQUIRED_ENV_KEYS=("GCP_PROJECT" "VERTEX_REGION" "GCS_BUCKET_SNAPSHOTS" "PROCESSED_TOPIC")
MISSING_ENVS=""
for key in "${REQUIRED_ENV_KEYS[@]}"; do
  if ! echo "$FUNC_ENV_KEYS" | grep -qxF "$key"; then
    MISSING_ENVS="$MISSING_ENVS $key"
  fi
done

if [[ "$FUNC_STATE" != "ACTIVE" ]]; then
  fail_test "$N" "$LABEL" "state='$FUNC_STATE' (want ACTIVE)"
elif [[ -n "$MISSING_ENVS" ]]; then
  fail_test "$N" "$LABEL" "missing env vars:$MISSING_ENVS"
else
  pass_test "$N" "$LABEL"
  echo "       state: $FUNC_STATE"
fi

# ═══════════════════════════════════════════════════════════════
# [10/14] Firestore reachable
# ═══════════════════════════════════════════════════════════════
N=10
LABEL="firestore reachable (databases list has '(default)')"
ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
if [[ -z "$ACCESS_TOKEN" ]]; then
  fail_test "$N" "$LABEL" "no access token (run: gcloud auth login)"
else
  HTTP_CODE=$(curl -s -o /tmp/ithuriel_firestore.json -w "%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://firestore.googleapis.com/v1/projects/$GCP_PROJECT/databases" \
    2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "200" ]]; then
    fail_test "$N" "$LABEL" "HTTP $HTTP_CODE from Firestore API"
  elif ! grep -q '(default)' /tmp/ithuriel_firestore.json; then
    fail_test "$N" "$LABEL" "response does not contain '(default)' — body: $(cat /tmp/ithuriel_firestore.json)"
  else
    pass_test "$N" "$LABEL"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# [11/14] Pub/Sub topics exist
# ═══════════════════════════════════════════════════════════════
N=11
LABEL="pub/sub: all 3 ithuriel topics exist"
REQUIRED_TOPICS=(
  "ithuriel-snapshots"
  "ithuriel-snapshots-processed"
  "ithuriel-agent-runs"
)
# Topic names are full resource paths: projects/PROJECT/topics/NAME
# List all topics and grep for the short name in the path
TOPIC_LIST=$(gcloud pubsub topics list \
  --format=value\(name\) \
  2>/dev/null || true)

MISSING_TOPICS=""
for topic in "${REQUIRED_TOPICS[@]}"; do
  if ! echo "$TOPIC_LIST" | grep -qF "topics/$topic"; then
    MISSING_TOPICS="$MISSING_TOPICS $topic"
  fi
done

if [[ -n "$MISSING_TOPICS" ]]; then
  fail_test "$N" "$LABEL" "missing topics:$MISSING_TOPICS"
else
  pass_test "$N" "$LABEL"
  echo "$TOPIC_LIST" | grep ithuriel | while read -r t; do echo "       $t"; done
fi

# ═══════════════════════════════════════════════════════════════
# [12/14] GCS bucket exists
# ═══════════════════════════════════════════════════════════════
N=12
LABEL="gcs bucket '$GCS_BUCKET' exists"
BUCKET_OUTPUT=$(gcloud storage buckets describe "$GCS_BUCKET" 2>&1 || true)
if echo "$BUCKET_OUTPUT" | grep -q "name:"; then
  pass_test "$N" "$LABEL"
elif echo "$BUCKET_OUTPUT" | grep -qi "not found\|does not exist\|404\|ERROR"; then
  fail_test "$N" "$LABEL" "bucket not found or inaccessible"
else
  # Try alternate check
  BUCKET_OUTPUT2=$(gcloud storage buckets list --filter="name=$GCS_BUCKET" --format="value(name)" 2>/dev/null || true)
  if [[ -n "$BUCKET_OUTPUT2" ]]; then
    pass_test "$N" "$LABEL"
  else
    fail_test "$N" "$LABEL" "bucket not found: $BUCKET_OUTPUT"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# [13/14] Firebase Web API key live
# ═══════════════════════════════════════════════════════════════
N=13
LABEL="firebase web API key live (accounts:lookup → 400 INVALID_ID_TOKEN)"
# The /v1/projects endpoint is not publicly accessible; instead, call accounts:lookup
# with a dummy token. A valid API key returns 400 INVALID_ID_TOKEN.
# A bad key or disabled project returns 403 or 404.
HTTP_CODE=$(curl -s -o /tmp/ithuriel_firebase.json -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$FIREBASE_WEB_API_KEY" \
  -d '{"idToken":"smoke-test-dummy-token"}' \
  2>/dev/null || echo "000")
ERROR_MSG=$(jq -r '.error.message // empty' /tmp/ithuriel_firebase.json 2>/dev/null || true)
if [[ "$HTTP_CODE" == "400" && "$ERROR_MSG" == "INVALID_ID_TOKEN" ]]; then
  # 400 INVALID_ID_TOKEN confirms the key is valid and the project is reachable
  pass_test "$N" "$LABEL"
  echo "       API key accepted by Firebase (INVALID_ID_TOKEN for dummy token confirms key is live)"
elif [[ "$HTTP_CODE" == "200" ]]; then
  pass_test "$N" "$LABEL"
else
  fail_test "$N" "$LABEL" "HTTP $HTTP_CODE${ERROR_MSG:+ — $ERROR_MSG} (expected 400 INVALID_ID_TOKEN)"
fi

# ═══════════════════════════════════════════════════════════════
# [14/14] Cloud Run API env vars
# ═══════════════════════════════════════════════════════════════
N=14
LABEL="cloud run 'ithuriel-api' env vars present"
REQUIRED_RUN_ENVS=("GCP_PROJECT" "VERTEX_REGION" "GCS_BUCKET_SNAPSHOTS" "PUBSUB_TOPIC_SNAPSHOTS")
CR_ENVS=$(gcloud run services describe ithuriel-api \
  --region="$REGION" \
  --format='json' \
  2>/dev/null | jq -r \
  '.spec.template.spec.containers[0].env[]? | .name' \
  2>/dev/null || true)

MISSING_CR_ENVS=""
for key in "${REQUIRED_RUN_ENVS[@]}"; do
  if ! echo "$CR_ENVS" | grep -qxF "$key"; then
    MISSING_CR_ENVS="$MISSING_CR_ENVS $key"
  fi
done

if [[ -n "$MISSING_CR_ENVS" ]]; then
  fail_test "$N" "$LABEL" "missing env vars:$MISSING_CR_ENVS"
else
  pass_test "$N" "$LABEL"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
if [[ $FAILED -eq 0 ]]; then
  echo -e "${BOLD}  ${GREEN}PASSED: $PASSED/$TOTAL — all checks green${RESET}${BOLD}  ${RESET}"
else
  echo -e "${BOLD}  ${GREEN}PASSED: $PASSED/$TOTAL${RESET}${BOLD}   ${RED}FAILED: $FAILED/$TOTAL${RESET}"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""

[[ $FAILED -eq 0 ]]
