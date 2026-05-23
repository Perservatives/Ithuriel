#!/usr/bin/env node
// stdio transport — for Claude Desktop, Claude Code, Cursor, and other
// local clients that spawn the MCP server as a child process.
//
// Reads ITHURIEL_API_URL and ITHURIEL_API_TOKEN from the environment.

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { buildServer } from "./server.js";

async function main() {
  const apiBaseURL = process.env.ITHURIEL_API_URL ?? "https://api.ithuriel.dev";
  const token = process.env.ITHURIEL_API_TOKEN ?? "";
  if (!token) {
    console.error(
      "ithuriel-mcp: ITHURIEL_API_TOKEN is required. " +
        "Set it to a Firebase ID token (preferred) or the dev bearer token " +
        "from the macOS app's Settings → Integrations.",
    );
    process.exit(1);
  }

  const server = buildServer({ apiBaseURL, resolveToken: () => token });
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("ithuriel-mcp fatal:", err);
  process.exit(1);
});
