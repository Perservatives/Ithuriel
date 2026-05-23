import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";
import { publish } from "../lib/pubsub.js";
import { writeJSON } from "../lib/storage.js";

const TOPIC  = process.env.PUBSUB_TOPIC_SNAPSHOTS  ?? "ithuriel-snapshots";
const BUCKET = process.env.GCS_BUCKET_SNAPSHOTS    ?? "";

export async function snapshotRoutes(app: FastifyInstance) {
  app.post<{ Body: Record<string, unknown> }>("/context/snapshot", async (req, reply) => {
    const uid = req.uid!;
    const body = (req.body ?? {}) as Record<string, unknown> & { id?: string; capturedAt?: string };
    const id   = (body.id as string) ?? crypto.randomUUID();
    const ts   = body.capturedAt ? new Date(body.capturedAt as string) : new Date();
    const path = `${uid}/${id}.json`;

    if (!BUCKET) return reply.code(500).send({ error: "GCS_BUCKET_SNAPSHOTS not configured" });

    const rawRef = await writeJSON(BUCKET, path, body);

    const doc = {
      id,
      userId:        uid,
      capturedAt:    ts,
      receivedAt:    new Date(),
      source:        body.source ?? "unknown",
      workspacePath: body.workspacePath ?? null,
      gitBranch:     (body as any).gitState?.branch ?? null,
      gitCommit:     (body as any).gitState?.lastCommit ?? null,
      activeFiles:   ((body as any).activeFiles ?? []) as string[],
      editCount:     Array.isArray((body as any).recentEdits) ? (body as any).recentEdits.length : 0,
      rawRef,
      // summaries populated by the Cloud Function processor
      summaryShort:  null,
      summaryMedium: null,
      summaryFull:   null,
      embeddingRef:  null,
    };

    await firestore().collection("snapshots").doc(id).set(doc);
    await firestore().collection("users").doc(uid).collection("snapshots").doc(id).set({ id, capturedAt: ts });

    const messageId = await publish(TOPIC, { snapshotId: id, userId: uid, rawRef });
    return { id, messageId, rawRef };
  });
}
