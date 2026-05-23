import type { FastifyInstance } from "fastify";

export async function healthRoutes(app: FastifyInstance) {
  app.get("/health", async () => ({ status: "ok", ts: new Date().toISOString() }));
  app.get("/v1/health", async () => ({ status: "ok", ts: new Date().toISOString() }));
}
