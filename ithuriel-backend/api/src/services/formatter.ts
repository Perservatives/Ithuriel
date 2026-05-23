import type { ContextFormat, ProcessedSnapshot, SnapshotMetadata } from "../models.js";

type FormattableSnapshot = Pick<
  ProcessedSnapshot,
  | "summaryFull"
  | "summaryMedium"
  | "summaryShort"
  | "activeFiles"
  | "recentEdits"
  | "terminalHistory"
  | "gitBranch"
  | "gitCommit"
  | "source"
>;

function summary(snapshot: FormattableSnapshot): string {
  return (
    snapshot.summaryFull ??
    snapshot.summaryMedium ??
    snapshot.summaryShort ??
    "No processed summary available."
  );
}

export function formatForClaude(snapshot: FormattableSnapshot): string {
  const lines = [
    "# Project Context",
    "",
    "## Current task",
    summary(snapshot),
    "",
    "## Active files",
    snapshot.activeFiles.length
      ? snapshot.activeFiles.map((f) => `- ${f}`).join("\n")
      : "_None reported_",
    "",
    "## Recent changes",
    snapshot.recentEdits.length
      ? snapshot.recentEdits.map((e) => `- ${e}`).join("\n")
      : "_None reported_",
    "",
    "## Git context",
    `- Branch: \`${snapshot.gitBranch || "unknown"}\``,
    `- Commit: \`${snapshot.gitCommit || "unknown"}\``,
    `- Source: ${snapshot.source}`,
    "",
    "## Terminal history",
    snapshot.terminalHistory.length
      ? "```\n" + snapshot.terminalHistory.slice(-20).join("\n") + "\n```"
      : "_No terminal history_",
  ];
  return lines.join("\n");
}

export function formatForCursor(snapshot: FormattableSnapshot): string {
  return [
    "---",
    "description: Ithuriel project context (auto-generated)",
    "globs:",
    "alwaysApply: true",
    "---",
    "",
    "# Project context",
    "",
    summary(snapshot),
    "",
    "## Active files",
    snapshot.activeFiles.map((f) => `- ${f}`).join("\n") || "_None_",
    "",
    "## Git",
    `Branch: ${snapshot.gitBranch} | Commit: ${snapshot.gitCommit}`,
  ].join("\n");
}

export function formatForChatGPT(snapshot: FormattableSnapshot): string {
  return `Here is the current project context:\n\n${summary(snapshot)}\n\nActive files: ${snapshot.activeFiles.join(", ") || "none"}\nGit: ${snapshot.gitBranch}@${snapshot.gitCommit?.slice(0, 7) ?? "unknown"}`;
}

export function formatForCopilot(snapshot: FormattableSnapshot): string {
  const compact = summary(snapshot).replace(/\n+/g, " ").slice(0, 2000);
  return `/* Ithuriel context | ${snapshot.gitBranch} | files: ${snapshot.activeFiles.slice(0, 5).join(", ")} */\n// ${compact}`;
}

export function formatSnapshot(
  snapshot: FormattableSnapshot,
  format: ContextFormat
): string {
  switch (format) {
    case "claude":
      return formatForClaude(snapshot);
    case "cursor":
      return formatForCursor(snapshot);
    case "chatgpt":
      return formatForChatGPT(snapshot);
    case "copilot":
      return formatForCopilot(snapshot);
    default:
      return formatForClaude(snapshot);
  }
}

export function toFormattable(
  meta: SnapshotMetadata
): FormattableSnapshot | null {
  if (meta.status !== "ready" && !meta.summaryFull) {
    return null;
  }
  return {
    summaryFull: meta.summaryFull ?? "",
    summaryMedium: meta.summaryMedium,
    summaryShort: meta.summaryShort,
    activeFiles: meta.activeFiles,
    recentEdits: meta.recentEdits,
    terminalHistory: meta.terminalHistory,
    gitBranch: meta.gitBranch,
    gitCommit: meta.gitCommit,
    source: meta.source,
  };
}
