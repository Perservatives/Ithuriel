import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { verifyFirebaseToken } from "../auth.js";
const broadcastSchema = z.object({
  teamId: z.string().min(1).max(128),
  message: z.string().min(1).max(8192),
  metadata: z.record(z.string()).optional(),
});

export async function teamRoutes(app: FastifyInstance): Promise<void> {
  app.post(
    "/v1/team/broadcast",
    { preHandler: verifyFirebaseToken },
    async (request, reply) => {
      const parsed = broadcastSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "ValidationError",
          details: parsed.error.flatten(),
        });
      }

      const uid = request.user!.uid;
      const topic = process.env.PUBSUB_TEAM_TOPIC ?? "ithuriel-team-broadcast";
      const data = Buffer.from(
        JSON.stringify({
          uid,
          teamId: parsed.data.teamId,
          message: parsed.data.message,
          metadata: parsed.data.metadata ?? {},
          sentAt: new Date().toISOString(),
        })
      );

      const { pubsub } = await import("../services/pubsub.js");
      await pubsub.topic(topic).publishMessage({ data });

      return reply.code(202).send({ status: "broadcast_queued", teamId: parsed.data.teamId });
    }
  );
}
