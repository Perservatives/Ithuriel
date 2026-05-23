import type { FastifyInstance, FastifyRequest, FastifyReply } from "fastify";
import fp from "fastify-plugin";
import { auth } from "./lib/firebase.js";

declare module "fastify" {
  interface FastifyRequest {
    uid?: string;
  }
}

const PUBLIC_PREFIXES = ["/health", "/auth/", "/v1/health"];

// Wrapped with fastify-plugin so the preHandler hook escapes plugin
// encapsulation and applies to every route registered on the root app
// (including sibling-registered route plugins). Without this, the auth
// hook only fires on routes registered *inside* this plugin's scope —
// so /v1/context/* would hit Firestore with req.uid undefined and crash
// with a 500 instead of returning 401.
export const authPlugin = fp(async (app: FastifyInstance) => {
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
});
