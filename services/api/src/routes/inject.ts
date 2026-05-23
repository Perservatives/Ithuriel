import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";

type Target = "claude-code" | "cursor" | "chatgpt" | "claude-desktop" | "copilot-chat" | "gemini";

export async function injectRoutes(app: FastifyInstance) {
  app.post<{ Body: { target?: Target; snapshotId?: string } }>("/context/inject", async (req, reply) => {
    const uid = req.uid!;
    const target = (req.body?.target ?? "claude-code") as Target;

    let snap;
    if (req.body?.snapshotId) {
      const d = await firestore().collection("snapshots").doc(req.body.snapshotId).get();
      if (!d.exists || d.data()?.userId !== uid) return reply.code(404).send({ error: "not found" });
      snap = d.data();
    } else {
      const q = await firestore()
        .collection("snapshots").where("userId", "==", uid)
        .orderBy("capturedAt", "desc").limit(1).get();
      if (q.empty) return reply.code(404).send({ error: "no snapshots" });
      snap = q.docs[0]!.data();
    }

    return { target, payload: format(target, snap as any) };
  });
}

function format(target: Target, s: any): string {
  switch (target) {
    case "claude-code":
    case "claude-desktop":
      return claudeMd(s);
    case "cursor":
    case "copilot-chat":
      return cursorRules(s);
    default:
      return systemMessage(s);
  }
}

function claudeMd(s: any): string {
  const lines: string[] = ["# Project context", ""];
  if (s.workspacePath) lines.push(`Workspace: ${s.workspacePath}`);
  if (s.gitBranch)     lines.push(`Branch: ${s.gitBranch}`);
  if (s.gitCommit)     lines.push(`Last commit: ${s.gitCommit}`);
  if (s.summaryFull)   lines.push("", s.summaryFull);
  if (Array.isArray(s.activeFiles) && s.activeFiles.length) {
    lines.push("", "Active files:");
    for (const f of s.activeFiles.slice(0, 10)) lines.push(`  - ${f}`);
  }
  return lines.join("\n");
}

function cursorRules(s: any): string {
  let out = `You are working in: ${s.workspacePath ?? "(unknown workspace)"}\n`;
  if (s.gitBranch) out += `Active branch: ${s.gitBranch}.\n`;
  if (s.summaryMedium) out += `\n${s.summaryMedium}\n`;
  return out;
}

function systemMessage(s: any): string {
  return s.summaryShort ?? s.summaryMedium ?? `I am working on ${s.workspacePath ?? "a project"}.`;
}
