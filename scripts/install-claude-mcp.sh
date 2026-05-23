#!/usr/bin/env bash
# Installs the Ithuriel MCP connector into Claude Desktop, Claude Code, and
# Cursor — whichever are installed on this Mac.
#
# Usage:
#   ./scripts/install-claude-mcp.sh            # prompts for token
#   ./scripts/install-claude-mcp.sh --token T  # token via flag
#   ITHURIEL_TOKEN=T ./scripts/install-claude-mcp.sh
#
# Optional:
#   ITHURIEL_API_URL=https://...  # default: prod Cloud Run

set -euo pipefail

# --- Args ---
TOKEN="${ITHURIEL_TOKEN:-}"
API_URL="${ITHURIEL_API_URL:-https://ithuriel-api-596592790807.us-central1.run.app}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) TOKEN="$2"; shift 2 ;;
    --api)   API_URL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TOKEN" ]]; then
  echo -n "Paste your Ithuriel bearer token (Settings → Integrations): "
  read -rs TOKEN
  echo
fi

if [[ -z "$TOKEN" ]]; then
  echo "no token provided — aborting." >&2
  exit 2
fi

# --- Build MCP server ---
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MCP_DIR="$REPO/services/mcp"
DIST="$MCP_DIR/dist/stdio.js"

if [[ ! -f "$DIST" ]]; then
  echo "→ Building MCP server (one-time)…"
  ( cd "$MCP_DIR" && npm install --silent && npm run --silent build )
fi

if [[ ! -f "$DIST" ]]; then
  echo "build did not produce $DIST — check services/mcp logs." >&2
  exit 1
fi

# --- Helpers ---

# Merge { mcpServers: { ithuriel: {...} } } into the given config file using a
# small node one-liner. Works on macOS without jq, and preserves any existing
# mcpServers entries the user already configured.
merge_mcp() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || echo '{}' > "$file"

  node - "$file" "$DIST" "$API_URL" "$TOKEN" <<'JS'
const fs = require('fs');
const [, , file, dist, apiUrl, token] = process.argv;
const raw = fs.readFileSync(file, 'utf8').trim() || '{}';
let json;
try { json = JSON.parse(raw); } catch (e) {
  console.error('  (existing file not valid JSON — refusing to overwrite)');
  process.exit(1);
}
json.mcpServers = json.mcpServers || {};
json.mcpServers.ithuriel = {
  command: 'node',
  args: [dist],
  env: {
    ITHURIEL_API_URL: apiUrl,
    ITHURIEL_API_TOKEN: token
  }
};
fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n');
JS
}

install_for() {
  local name="$1"
  local file="$2"
  local app_path="$3"
  if [[ -n "$app_path" && ! -e "$app_path" ]]; then
    echo "—  $name not installed, skipping."
    return
  fi
  if merge_mcp "$file"; then
    echo "✓  $name → $file"
    INSTALLED+=("$name")
  fi
}

INSTALLED=()

# Claude Desktop
install_for "Claude Desktop" \
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
  "/Applications/Claude.app"

# Claude Code (CLI ships with no .app — config lives at ~/.claude.json regardless)
install_for "Claude Code" \
  "$HOME/.claude.json" \
  ""

# Cursor
install_for "Cursor" \
  "$HOME/.cursor/mcp.json" \
  "/Applications/Cursor.app"

echo
if [[ ${#INSTALLED[@]} -eq 0 ]]; then
  echo "Nothing installed — install at least one of Claude Desktop / Claude Code / Cursor and re-run."
  exit 1
fi

echo "Restart these to pick up the connector:"
for app in "${INSTALLED[@]}"; do echo "  • $app"; done
echo
echo "Done. Verify by asking the client: \"Use the get_current_context tool.\""
