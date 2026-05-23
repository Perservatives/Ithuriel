import type { FastifyInstance } from "fastify";
import { FieldValue } from "firebase-admin/firestore";
import { firestore } from "../lib/firebase.js";
import { Storage } from "@google-cloud/storage";
import { embed, cosine } from "../lib/vertex.js";

const BUCKET = process.env.GCS_BUCKET_SNAPSHOTS ?? "";
const storage = new Storage({ projectId: process.env.GCP_PROJECT });

interface SearchBody {
  query: string;
  k?: number;
}

/**
 * Semantic search over the signed-in user's processed snapshots. Embeds the
 * query with Vertex AI text-embedding-005, then runs Firestore native
 * `findNearest()` (KNN, COSINE distance) against the per-doc Vector field
 * written by the processor.
 *
 * Falls back to a small GCS+cosine scan for snapshots predating the
 * Vector-field migration so the API stays useful while the processor
 * back-fills old rows.
 */
export async function searchRoutes(app: FastifyInstance) {
  app.post<{ Body: SearchBody }>("/context/search", async (req, reply) => {
    const uid = req.uid!;
    const q   = (req.body?.query ?? "").trim();
    if (!q) return reply.code(400).send({ error: "empty query" });
    const k = Math.min(Math.max(Number(req.body?.k ?? 6), 1), 20);

    let queryVec: number[];
    try {
      queryVec = await embed(q);
    } catch (err) {
      app.log.error({ err }, "vertex embed failed");
      return reply.code(502).send({ error: "embedding failed" });
    }

    // Native Firestore KNN. Requires the
    // snapshots.embedding vector index from infra/firestore.indexes.json.
    try {
      const snap = await firestore()
        .collection("snapshots")
        .where("userId", "==", uid)
        .findNearest({
          vectorField: "embedding",
          queryVector: FieldValue.vector(queryVec),
          limit: k,
          distanceMeasure: "COSINE",
          distanceResultField: "_distance",
        })
        .get();

      if (!snap.empty) {
        const items = snap.docs.map((d) => {
          const data = d.data() as any;
          const { embedding, _distance, ...rest } = data;
          return {
            snapshot: rest,
            // Cosine distance ∈ [0,2]; convert to a 0…1 similarity score.
            score: typeof _distance === "number" ? 1 - _distance / 2 : null,
          };
        });
        return { items, query: q, mode: "knn" };
      }
    } catch (err) {
      // Likely cause: vector index not yet built. Fall through to legacy scan.
      app.log.warn({ err }, "findNearest failed, falling back to GCS scan");
    }

    // Fallback: scan recent snapshot embeddings out of GCS and cosine-rank.
    const docs = await firestore()
      .collection("snapshots")
      .where("userId", "==", uid)
      .orderBy("capturedAt", "desc")
      .limit(200)
      .get();
    if (docs.empty) return { items: [], query: q, mode: "empty" };

    const candidates = await Promise.all(
      docs.docs.map(async (d) => {
        const data = d.data() as { embeddingRef?: string };
        if (!data.embeddingRef) return null;
        const vec = await loadEmbedding(data.embeddingRef);
        if (!vec) return null;
        return { doc: d.data(), score: cosine(queryVec, vec) };
      }),
    );

    const ranked = candidates
      .filter((x): x is { doc: any; score: number } => x !== null)
      .sort((a, b) => b.score - a.score)
      .slice(0, k);

    return {
      items: ranked.map(({ doc, score }) => ({ snapshot: doc, score })),
      query: q,
      mode: "fallback",
    };
  });
}

async function loadEmbedding(ref: string): Promise<number[] | null> {
  // ref shape: "gs://<bucket>/<path>"
  if (!ref.startsWith("gs://")) return null;
  const rest = ref.slice(5);
  const slash = rest.indexOf("/");
  if (slash < 0) return null;
  const bucket = rest.slice(0, slash);
  const path   = rest.slice(slash + 1);
  try {
    const [buf] = await storage.bucket(bucket || BUCKET).file(path).download();
    return JSON.parse(buf.toString("utf-8")) as number[];
  } catch {
    return null;
  }
}
