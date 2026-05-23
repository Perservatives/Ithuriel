import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import { randomUUID } from "node:crypto";
import { contextRoutes } from "./routes/context.js";
import { healthRoutes } from "./routes/health.js";
import { teamRoutes } from "./routes/team.js";
import { registerWebSocket } from "./websocket.js";

const port = parseInt(process.env.PORT ?? "8080", 10);
const host = process.env.HOST ?? "0.0.0.0";

const app = Fastify({
  logger: {
    level: process.env.LOG_LEVEL ?? "info",
  },
  requestIdHeader: "x-request-id",
  genReqId: (req) =>
    (req.headers["x-request-id"] as string | undefined) ?? randomUUID(),
});

await app.register(cors, { origin: true });
await app.register(websocket);

app.addHook("onSend", async (request, reply, payload) => {
  reply.header("x-request-id", request.id);
  return payload;
});

await app.register(healthRoutes);
await app.register(contextRoutes);
await app.register(teamRoutes);
await registerWebSocket(app);

app.setErrorHandler((error, request, reply) => {
  request.log.error({ err: error, requestId: request.id }, "request failed");
  const statusCode = error.statusCode ?? 500;
  reply.code(statusCode).send({
    error: error.name ?? "InternalServerError",
    message: statusCode >= 500 ? "Internal server error" : error.message,
    requestId: request.id,
  });
});

try {
  await app.listen({ port, host });
  app.log.info({ port, host }, "ithuriel-api listening");
} catch (err) {
  app.log.fatal(err);
  process.exit(1);
}
