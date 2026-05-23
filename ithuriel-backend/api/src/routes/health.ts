import type { FastifyInstance } from "fastify";

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/v1/health", async () => ({
    status: "ok",
    service: "ithuriel-api",
    timestamp: new Date().toISOString(),
  }));
}
