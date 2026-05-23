// Streamable-HTTP transport — for ChatGPT Developer-mode custom connectors
// and Claude.ai custom connectors (both require a public HTTPS MCP endpoint).
//
// Endpoint: POST /mcp     — JSON-RPC over HTTP with optional SSE upgrade
// Endpoint: GET  /mcp     — opens an SSE stream for server-initiated events
// Endpoint: GET  /health  — for Cloud Run readiness checks
//
// Auth: the inbound `Authorization: Bearer <token>` is forwarded verbatim
// to the Ithuriel API on every tool call. The token is *not* persisted
// server-side — each MCP request runs in its own short-lived context.

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { buildServer } from "./server.js";

const PORT = Number(process.env.PORT ?? 8081);
const API_BASE_URL = process.env.ITHURIEL_API_URL ?? "https://api.ithuriel.dev";

function extractBearer(req: IncomingMessage): string | null {
  const h = req.headers.authorization;
  if (!h) return null;
  const [scheme, value] = h.split(" ", 2);
  if (!scheme || scheme.toLowerCase() !== "bearer" || !value) return null;
  return value.trim();
}

async function handle(req: IncomingMessage, res: ServerResponse) {
  // CORS — Claude.ai and ChatGPT call us from the browser-hosted client.
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "authorization, content-type, mcp-session-id");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, DELETE");
  res.setHeader("Access-Control-Expose-Headers", "mcp-session-id");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);

  if (url.pathname === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  if (url.pathname !== "/mcp") {
    res.writeHead(404);
    res.end("not found");
    return;
  }

  const token = extractBearer(req);
  if (!token) {
    res.writeHead(401, {
      "content-type": "application/json",
      "www-authenticate": 'Bearer realm="ithuriel"',
    });
    res.end(JSON.stringify({ error: "missing bearer token" }));
    return;
  }

  // One server + transport per request keeps token resolution stateless
  // and avoids cross-tenant leakage. Streamable-HTTP supports this.
  const server = buildServer({ apiBaseURL: API_BASE_URL, resolveToken: () => token });
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // stateless mode
    enableJsonResponse: true,
  });

  res.on("close", () => {
    transport.close().catch(() => {});
    server.close().catch(() => {});
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res);
  } catch (err) {
    console.error("mcp handler error:", err);
    if (!res.headersSent) {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: String(err) }));
    }
  }
}

const httpServer = createServer((req, res) => {
  handle(req, res).catch((err) => {
    console.error("unhandled:", err);
    if (!res.headersSent) res.writeHead(500).end();
  });
});

httpServer.listen(PORT, "0.0.0.0", () => {
  console.log(`ithuriel-mcp listening on :${PORT} → ${API_BASE_URL}`);
});
