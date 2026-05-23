import type { FastifyInstance, FastifyRequest, FastifyReply } from "fastify";
import { auth } from "./lib/firebase.js";

declare module "fastify" {
  interface FastifyRequest {
    uid?: string;
  }
}

const PUBLIC_PREFIXES = ["/health", "/auth/", "/v1/health"];

export async function authPlugin(app: FastifyInstance) {
  app.addHook("preHandler", async (req: FastifyRequest, reply: FastifyReply) => {
    if (PUBLIC_PREFIXES.some((p) => req.url.startsWith(p))) return;

    const header = req.headers.authorization ?? "";
    const match  = header.match(/^Bearer (.+)$/);
    if (!match) {
      reply.code(401).send({ error: "missing bearer token" });
      return reply;
    }
    try {
      const decoded = await auth().verifyIdToken(match[1]!);
      req.uid = decoded.uid;
    } catch (err) {
      req.log.warn({ err }, "token verification failed");
      reply.code(401).send({ error: "invalid token" });
      return reply;
    }
  });
}
