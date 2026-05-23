import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";

export async function currentRoutes(app: FastifyInstance) {
  app.get<{ Querystring: { format?: string } }>("/context/current", async (req, reply) => {
    const uid = req.uid!;
    const snap = await firestore()
      .collection("snapshots")
      .where("userId", "==", uid)
      .orderBy("capturedAt", "desc")
      .limit(1)
      .get();
    if (snap.empty) return reply.code(404).send({ error: "no snapshots" });
    const doc = snap.docs[0]!.data();
    return doc;
  });

  app.get<{ Params: { id: string } }>("/context/:id", async (req, reply) => {
    const doc = await firestore().collection("snapshots").doc(req.params.id).get();
    if (!doc.exists) return reply.code(404).send({ error: "not found" });
    const data = doc.data();
    if (data?.userId !== req.uid) return reply.code(403).send({ error: "forbidden" });
    return data;
  });
}
