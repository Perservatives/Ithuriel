import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";
import { publish } from "../lib/pubsub.js";

const TOPIC = process.env.PUBSUB_TOPIC_AGENT_RUNS ?? "ithuriel-agent-runs";

interface RunBody {
  id?: string;
  task: string;
  startedAt?: string;
  finishedAt?: string;
  status: "running" | "completed" | "failed" | "killed";
  transcript: string[];
  error?: string | null;
  snapshotId?: string | null;
}

export async function agentRunRoutes(app: FastifyInstance) {
  // Create or upsert a run.
  app.post<{ Body: RunBody }>("/agent/run", async (req, reply) => {
    const uid = req.uid!;
    const id  = req.body.id ?? crypto.randomUUID();
    const doc = {
      id,
      userId:     uid,
      task:       req.body.task,
      status:     req.body.status,
      startedAt:  req.body.startedAt  ? new Date(req.body.startedAt)  : new Date(),
      finishedAt: req.body.finishedAt ? new Date(req.body.finishedAt) : null,
      transcript: req.body.transcript ?? [],
      error:      req.body.error ?? null,
      snapshotId: req.body.snapshotId ?? null,
      updatedAt:  new Date(),
    };
    await firestore().collection("agentRuns").doc(id).set(doc, { merge: true });
    if (req.body.status === "completed" || req.body.status === "failed" || req.body.status === "killed") {
      await publish(TOPIC, { runId: id, userId: uid, status: req.body.status });
    }
    return { id };
  });

  app.get<{ Querystring: { limit?: string } }>("/agent/runs", async (req) => {
    const uid   = req.uid!;
    const limit = Math.min(Number(req.query.limit ?? 25), 100);
    const snap  = await firestore()
      .collection("agentRuns")
      .where("userId", "==", uid)
      .orderBy("startedAt", "desc")
      .limit(limit)
      .get();
    return { items: snap.docs.map((d) => d.data()) };
  });
}
