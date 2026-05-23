# Connect Ithuriel to Claude and ChatGPT

Ithuriel ships a single Model Context Protocol (MCP) server that exposes
your live workspace context — current snapshot, git state, recent edits,
terminal history, agent runs — to every modern AI client. Both Anthropic
and OpenAI standardised on MCP, so one server covers all of them.

> **TL;DR**
> ```
> ./scripts/install-claude-mcp.sh
> ```
> writes the right config into Claude Desktop, Claude Code, and Cursor.
> ChatGPT is a one-time UI step (see below).

The MCP server lives at `services/mcp/`. The implementation is
[`@modelcontextprotocol/sdk`](https://github.com/modelcontextprotocol/sdk)
in TypeScript, runs in two transports (stdio for local clients, HTTPS
for remote connectors), and is pure auth-passthrough — every request
must carry your Ithuriel bearer token.

---

## What Ithuriel exposes

| Tool | Purpose |
|---|---|
| `get_current_context` | Latest snapshot — workspace, branch, commit, active files, summaries |
| `get_context_history` | Recent snapshots in descending capture order |
| `get_snapshot` | One snapshot by id |
| `format_context_for_tool` | Pre-formatted handoff text (CLAUDE.md / `.cursorrules` / system message / etc.) |
| `list_agent_runs` | Recent Ithuriel agent runs |

Plus one MCP resource — `ithuriel://context/current` — which can be
`@`-mentioned in both Claude.ai and ChatGPT.

---

## Get your bearer token

1. Launch Ithuriel (the macOS app).
2. Open **Settings → Integrations**.
3. Tap **Reveal** next to "Bearer token", then **Copy**.

This is a Firebase ID token in production, or the static dev token
shown in Settings for local development. The MCP server forwards it
verbatim to the Ithuriel API and never persists it.

---

## Local clients (Claude Desktop / Claude Code / Cursor)

**One-shot setup:**

```bash
./scripts/install-claude-mcp.sh
```

This script:

1. Builds `services/mcp` (`npm install && npm run build`) if needed.
2. Prompts for your bearer token (or accepts it as `--token <…>`).
3. Writes the MCP config into the right file for whichever clients are
   installed:
   - Claude Desktop → `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Claude Code → `~/.claude.json`
   - Cursor → `~/.cursor/mcp.json`
4. Tells you which app(s) to restart.

**What it writes** (per client) looks like:

```json
{
  "mcpServers": {
    "ithuriel": {
      "command": "node",
      "args": ["<absolute-path>/services/mcp/dist/stdio.js"],
      "env": {
        "ITHURIEL_API_URL": "https://ithuriel-api-596592790807.us-central1.run.app",
        "ITHURIEL_API_TOKEN": "<your bearer token>"
      }
    }
  }
}
```

Restart the client, and **Ithuriel** appears in the tool / connector
list. In Claude Desktop and Claude Code you can `@ithuriel://context/current`
to drop the latest snapshot into any message.

---

## Remote clients (Claude.ai web / ChatGPT)

Both Claude.ai and ChatGPT only accept **HTTPS** MCP connectors. Deploy
the server to Cloud Run once and point both clients at the resulting
URL.

### 1. Deploy

```bash
PROJECT_ID=synthesis-hack26svl-121 REGION=us-central1

gcloud builds submit services/mcp \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/mcp:latest"

gcloud run deploy ithuriel-mcp \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/ithuriel/mcp:latest" \
  --region "$REGION" \
  --allow-unauthenticated \
  --port 8081 \
  --set-env-vars "ITHURIEL_API_URL=https://ithuriel-api-596592790807.us-central1.run.app"
```

Cloud Run prints a URL like `https://ithuriel-mcp-xxxx-uc.a.run.app`.
The MCP endpoint is `<url>/mcp`.

### 2. Wire ChatGPT

1. ChatGPT → **Settings → Connectors → Advanced → Developer mode**.
2. **Add custom connector**.
3. **Name:** `Ithuriel`
4. **MCP server URL:** `https://ithuriel-mcp-xxxx-uc.a.run.app/mcp`
5. **Authentication:** Bearer token → paste your Ithuriel token.

The Ithuriel tools show up in any conversation; you can also drop the
`ithuriel://context/current` resource into a prompt via `@`.

### 3. Wire Claude.ai

1. Claude.ai → **Settings → Connectors → Add custom connector**.
2. **Name:** `Ithuriel`
3. **Remote MCP server URL:** `https://ithuriel-mcp-xxxx-uc.a.run.app/mcp`
4. **Auth:** Bearer token → same token as above.

Claude Desktop can use the same remote URL via its Connectors panel if
you'd rather one shared connector across machines than a local stdio
install on each.

---

## How auth flows

```
You ──token──▶ MCP client (Claude / ChatGPT)
                   │
                   │  Authorization: Bearer <token>
                   ▼
           services/mcp (stdio or HTTPS)
                   │
                   │  Authorization forwarded verbatim
                   ▼
           services/api  (Cloud Run / local)
                   │
                   ▼
          Firestore / Vector Search / SwiftData
```

- MCP server is stateless. It holds no user data and no long-lived
  secrets.
- Token rotation: revoke on the API side; the connector stops working
  immediately. No MCP-side token table to keep in sync.
- For first-party dev, the macOS app shows a static dev token. For prod
  it issues short-lived Firebase ID tokens — paste once into the
  connector and rotation just works as long as the connector caches
  the bearer until expiry.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Client shows "Ithuriel" but tools return 401 | Bearer token is wrong or expired. Re-copy from Settings → Integrations. |
| `node` not found when running stdio | Install Node 20+: `brew install node`. Re-run `install-claude-mcp.sh`. |
| Claude Code says "MCP server crashed" | Build the server: `cd services/mcp && npm install && npm run build`. The script does this for you. |
| ChatGPT doesn't show the Developer-mode option | Custom MCP connectors require a Plus/Pro plan. |
| Cloud Run says 403 | Make sure you deployed with `--allow-unauthenticated`. The MCP server does its own bearer-token auth on top. |
