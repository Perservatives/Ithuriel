// Core MCP server. Transport-agnostic — wrapped by stdio.ts or http.ts.
//
// Exposes Ithuriel's workspace context to any MCP-speaking client
// (Claude Desktop, Claude Code, Claude.ai custom connector, ChatGPT
// Developer-mode custom connector, Cursor, etc).

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { IthurielAPI, type InjectTarget } from "./ithuriel.js";

export interface BuildOptions {
  apiBaseURL: string;
  // Resolves a bearer token at call time. For stdio this is a constant
  // from env; for HTTP it pulls the inbound Authorization header.
  resolveToken: () => string;
}

const TARGETS = [
  "claude-code",
  "claude-desktop",
  "cursor",
  "chatgpt",
  "copilot-chat",
  "gemini",
] as const satisfies readonly InjectTarget[];

export function buildServer(opts: BuildOptions): McpServer {
  const server = new McpServer(
    {
      name: "ithuriel",
      version: "1.0.0",
    },
    {
      // Help clients describe the connector in their UI.
      instructions:
        "Ithuriel exposes the user's live local development context — workspace path, " +
        "git state, active files, recent edits, and per-snapshot AI summaries — captured " +
        "by the Ithuriel macOS agent. Use `get_current_context` whenever the user refers " +
        "to 'my project', 'my repo', 'what I'm working on', or asks for help that depends " +
        "on their current code without specifying a path.",
    },
  );

  const api = () => new IthurielAPI(opts.apiBaseURL, opts.resolveToken());

  server.tool(
    "get_current_context",
    "Return the most recent workspace snapshot for the signed-in user: workspace path, " +
      "git branch and commit, active files, and short/medium/full AI summaries.",
    {},
    async () => {
      const snap = await api().currentContext();
      return {
        content: [
          { type: "text", text: renderSnapshot(snap) },
          { type: "text", text: JSON.stringify(snap, null, 2) },
        ],
      };
    },
  );

  server.tool(
    "get_context_history",
    "List recent workspace snapshots (most recent first) so you can show how the project evolved.",
    { limit: z.number().int().min(1).max(100).default(25) },
    async ({ limit }) => {
      const { items } = await api().history(limit);
      const lines = items.map(
        (s) =>
          `- ${s.capturedAt}  branch=${s.gitBranch ?? "?"}  commit=${(s.gitCommit ?? "").slice(0, 7)}  files=${(s.activeFiles ?? []).length}  id=${s.id}`,
      );
      return {
        content: [
          { type: "text", text: lines.join("\n") || "No snapshots yet." },
        ],
      };
    },
  );

  server.tool(
    "get_snapshot",
    "Fetch a single snapshot by id, including its full summary and active-file list.",
    { id: z.string().min(1) },
    async ({ id }) => {
      const snap = await api().snapshot(id);
      return { content: [{ type: "text", text: renderSnapshot(snap) }] };
    },
  );

  server.tool(
    "format_context_for_tool",
    "Format the latest context as a ready-to-paste system prompt for a specific AI tool " +
      "(claude-code → CLAUDE.md style, cursor → .cursorrules, chatgpt → plain system message, etc).",
    {
      target: z.enum(TARGETS),
      snapshotId: z.string().optional(),
    },
    async ({ target, snapshotId }) => {
      const { payload } = await api().formatForTarget(target, snapshotId);
      return { content: [{ type: "text", text: payload }] };
    },
  );

  server.tool(
    "list_agent_runs",
    "List recent Ithuriel agent runs (task, status, transcript length). Useful for asking " +
      "'what has my agent been doing lately' or for resuming a failed run.",
    { limit: z.number().int().min(1).max(100).default(25) },
    async ({ limit }) => {
      const { items } = await api().agentRuns(limit);
      const lines = items.map(
        (r) =>
          `- ${r.startedAt}  ${r.status.padEnd(9)}  steps=${r.transcript.length}  task="${r.task.slice(0, 80)}"`,
      );
      return {
        content: [
          { type: "text", text: lines.join("\n") || "No agent runs yet." },
        ],
      };
    },
  );

  // Resources let clients browse context like files. Claude.ai and
  // ChatGPT both surface MCP resources as @-mentionable attachments.
  server.resource(
    "current-context",
    "ithuriel://context/current",
    {
      title: "Current workspace context",
      description: "Live snapshot of the user's active project (auto-refreshes per read).",
      mimeType: "text/markdown",
    },
    async (uri) => {
      const snap = await api().currentContext();
      return {
        contents: [
          {
            uri: uri.href,
            mimeType: "text/markdown",
            text: renderSnapshot(snap),
          },
        ],
      };
    },
  );

  return server;
}

function renderSnapshot(s: {
  workspacePath?: string | null;
  gitBranch?: string | null;
  gitCommit?: string | null;
  activeFiles?: string[];
  summaryFull?: string | null;
  summaryMedium?: string | null;
  summaryShort?: string | null;
  capturedAt?: string;
}): string {
  const lines: string[] = ["# Ithuriel current context", ""];
  if (s.capturedAt) lines.push(`_Captured: ${s.capturedAt}_`, "");
  if (s.workspacePath) lines.push(`**Workspace:** \`${s.workspacePath}\``);
  if (s.gitBranch) lines.push(`**Branch:** \`${s.gitBranch}\``);
  if (s.gitCommit) lines.push(`**Last commit:** \`${s.gitCommit}\``);
  const summary = s.summaryFull ?? s.summaryMedium ?? s.summaryShort;
  if (summary) lines.push("", "## Summary", "", summary);
  if (Array.isArray(s.activeFiles) && s.activeFiles.length) {
    lines.push("", "## Active files", "");
    for (const f of s.activeFiles.slice(0, 25)) lines.push(`- \`${f}\``);
  }
  return lines.join("\n");
}
