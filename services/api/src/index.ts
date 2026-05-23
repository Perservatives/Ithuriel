import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import { initFirebase } from "./lib/firebase.js";
import { authPlugin } from "./auth.js";
import { healthRoutes } from "./routes/health.js";
import { snapshotRoutes } from "./routes/snapshot.js";
import { currentRoutes } from "./routes/current.js";
import { historyRoutes } from "./routes/history.js";
import { injectRoutes } from "./routes/inject.js";
import { agentRunRoutes } from "./routes/agentRun.js";
import { streamRoutes } from "./routes/stream.js";
import { teamRoutes } from "./routes/team.js";
import { authBridgeRoutes } from "./routes/authBridge.js";

const PORT = Number(process.env.PORT ?? 8080);
const ORIGINS = (process.env.ALLOWED_ORIGINS ?? "").split(",").filter(Boolean);

async function main() {
  initFirebase();
  const app = Fastify({
    logger: { level: process.env.LOG_LEVEL ?? "info" },
    trustProxy: true,
  });

  await app.register(cors, {
    origin: ORIGINS.length ? ORIGINS : true,
    credentials: true,
  });
  await app.register(websocket);
  await app.register(authPlugin);

  await app.register(healthRoutes);
  await app.register(authBridgeRoutes);             // unauth: /auth/google, /auth/callback
  await app.register(snapshotRoutes,  { prefix: "/v1" });
  await app.register(currentRoutes,   { prefix: "/v1" });
  await app.register(historyRoutes,   { prefix: "/v1" });
  await app.register(injectRoutes,    { prefix: "/v1" });
  await app.register(agentRunRoutes,  { prefix: "/v1" });
  await app.register(streamRoutes,    { prefix: "/v1" });
  await app.register(teamRoutes,      { prefix: "/v1" });

  await app.listen({ host: "0.0.0.0", port: PORT });
  app.log.info(`ithuriel-api listening on :${PORT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
