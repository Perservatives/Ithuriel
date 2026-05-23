import type { FastifyInstance } from "fastify";
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
 * query with Vertex AI text-embedding-005, scans up to the user's most recent
 * 200 snapshot embeddings from GCS, returns the top-K by cosine similarity.
 *
 * Replaces the "vector web" hack — every result is a real snapshot row from
 * Firestore with its summaries and metadata intact.
 */
export async function searchRoutes(app: FastifyInstance) {
  app.post<{ Body: SearchBody }>("/context/search", async (req, reply) => {
    const uid = req.uid!;
    const q   = (req.body?.query ?? "").trim();
    if (!q) return reply.code(400).send({ error: "empty query" });
    const k = Math.min(Math.max(Number(req.body?.k ?? 6), 1), 20);

    const docs = await firestore()
      .collection("snapshots")
      .where("userId", "==", uid)
      .orderBy("capturedAt", "desc")
      .limit(200)
      .get();

    if (docs.empty) return { items: [], query: q };

    const queryVec = await embed(q);

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

    return { items: ranked.map(({ doc, score }) => ({ snapshot: doc, score })), query: q };
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
