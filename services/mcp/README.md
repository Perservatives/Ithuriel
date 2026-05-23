# Ithuriel MCP connector

Exposes the user's live Ithuriel workspace context (current snapshot, git
state, summaries, agent runs) to any AI client that speaks the
**Model Context Protocol** (MCP):

- **Claude Desktop** and **Claude Code** — local stdio transport
- **Claude.ai web** — custom connector (remote HTTPS)
- **ChatGPT** (Developer mode) — custom MCP connector (remote HTTPS)
- **Cursor**, **Zed**, anything else MCP-capable — stdio

Both Anthropic and OpenAI standardized on MCP, so a single server here
covers every modern AI client. The server is auth-passthrough: each
request must carry an Ithuriel bearer token (Firebase ID token in prod,
static dev token from the macOS app's Settings panel in development).
The token is forwarded verbatim to `services/api` and never persisted.

---

## Tools

| Tool | Purpose |
|---|---|
| `get_current_context` | Latest snapshot — workspace, branch, commit, active files, summaries |
| `get_context_history` | Recent snapshots (descending by capture time) |
| `get_snapshot` | One snapshot by id |
| `format_context_for_tool` | Pre-formatted handoff text (CLAUDE.md / `.cursorrules` / etc.) |
| `list_agent_runs` | Recent Ithuriel agent runs |

Plus one resource: `ithuriel://context/current` — `@`-mentionable in
both Claude.ai and ChatGPT.

---

## Run locally (stdio — for Claude Desktop / Claude Code / Cursor)

```bash
cd services/mcp
npm install
npm run build
```

Then add to `~/Library/Application Support/Claude/claude_desktop_config.json`
(Claude Desktop) or `~/.claude.json` → `mcpServers` (Claude Code) or
`~/.cursor/mcp.json` (Cursor):

```json
{
  "mcpServers": {
    "ithuriel": {
      "command": "node",
      "args": ["/absolute/path/to/Ithuriel/services/mcp/dist/stdio.js"],
      "env": {
        "ITHURIEL_API_URL": "https://api.ithuriel.dev",
        "ITHURIEL_API_TOKEN": "<paste token from macOS app → Settings → Integrations>"
      }
    }
  }
}
```

Restart the client. Ithuriel will appear in the tools / connectors
list.

---

## Run as a remote connector (HTTPS — for Claude.ai + ChatGPT)

### 1. Deploy

The included `Dockerfile` is Cloud-Run-ready. From the repo root:

```bash
PROJECT_ID=ithuriel-prod-001 REGION=us-central1 \
gcloud builds submit services/mcp \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/mcp:latest"

gcloud run deploy ithuriel-mcp \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/mcp:latest" \
  --region "$REGION" \
  --allow-unauthenticated \
  --port 8081 \
  --set-env-vars "ITHURIEL_API_URL=https://api.ithuriel.dev"
```

This returns a URL like `https://ithuriel-mcp-xxxx-uc.a.run.app`. The
MCP endpoint is `<url>/mcp`.

### 2. Connect from ChatGPT

ChatGPT → **Settings → Connectors → Advanced → Developer mode**
→ **Add custom connector**:

- **Name:** Ithuriel
- **MCP server URL:** `https://ithuriel-mcp-xxxx-uc.a.run.app/mcp`
- **Authentication:** Bearer token → paste the Ithuriel token from the
  macOS app (Settings → Integrations → "Bearer token for Claude / ChatGPT")

### 3. Connect from Claude.ai

Claude.ai → **Settings → Connectors → Add custom connector**:

- **Name:** Ithuriel
- **Remote MCP server URL:** `https://ithuriel-mcp-xxxx-uc.a.run.app/mcp`
- **Auth:** Bearer token → same token as above

Claude Desktop also supports remote connectors via the same settings
panel. Use the remote URL there instead of the stdio config if you
want one shared connector across devices.

---

## Auth

The server is intentionally stateless — every MCP request carries its
own `Authorization: Bearer …` and that token is forwarded as-is to
`/v1/*` on the Ithuriel API. That means:

- The macOS app can issue short-lived Firebase ID tokens, drop them
  into a connector once, and rotation just works.
- The MCP server stores no user data and holds no long-lived secrets.
- Revocation is handled by the existing API auth layer — no separate
  MCP-side token table to keep in sync.

---

## Development

```bash
# stdio (talk to it from an MCP debugger like @modelcontextprotocol/inspector)
ITHURIEL_API_URL=http://localhost:8080 \
ITHURIEL_API_TOKEN=dev-token \
  npm run dev:stdio

# HTTP (curl / inspector)
ITHURIEL_API_URL=http://localhost:8080 \
  npm run dev:http
# → http://localhost:8081/mcp
```
