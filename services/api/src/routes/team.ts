import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";
import { publish } from "../lib/pubsub.js";

const TOPIC = process.env.PUBSUB_TOPIC_TEAM ?? "ithuriel-team-broadcast";

export async function teamRoutes(app: FastifyInstance) {
  app.post<{ Body: { teamId: string; snapshotId: string; note?: string } }>(
    "/team/broadcast",
    async (req, reply) => {
      const uid = req.uid!;
      const { teamId, snapshotId, note } = req.body;

      const team = await firestore().collection("teams").doc(teamId).get();
      if (!team.exists) return reply.code(404).send({ error: "team not found" });
      const members = (team.data()?.memberUids as string[] | undefined) ?? [];
      if (!members.includes(uid)) return reply.code(403).send({ error: "not a member" });

      await firestore().collection("teams").doc(teamId).update({
        sharedSnapshotId: snapshotId,
        sharedAt: new Date(),
        sharedBy: uid,
        sharedNote: note ?? null,
      });
      const messageId = await publish(TOPIC, { teamId, snapshotId, note, by: uid });
      return { messageId };
    },
  );
}
