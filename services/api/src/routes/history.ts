import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";

export async function historyRoutes(app: FastifyInstance) {
  app.get<{ Querystring: { limit?: string; cursor?: string } }>("/context/history", async (req) => {
    const uid    = req.uid!;
    const limit  = Math.min(Number(req.query.limit ?? 25), 100);
    const cursor = req.query.cursor;

    let q = firestore()
      .collection("snapshots")
      .where("userId", "==", uid)
      .orderBy("capturedAt", "desc")
      .limit(limit);

    if (cursor) {
      const cursorDoc = await firestore().collection("snapshots").doc(cursor).get();
      if (cursorDoc.exists) q = q.startAfter(cursorDoc);
    }

    const snap = await q.get();
    const items = snap.docs.map((d) => d.data());
    return {
      items,
      nextCursor: items.length === limit ? snap.docs[snap.docs.length - 1]?.id : null,
    };
  });
}
