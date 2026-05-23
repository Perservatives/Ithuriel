import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import { verifyTokenString } from "./auth.js";
import { watchUserSnapshots } from "./services/firestore.js";

const HEARTBEAT_MS = 30_000;
const MAX_MISSED_PINGS = 2;

interface StreamConnection {
  socket: WebSocket;
  uid: string;
  missedPings: number;
  heartbeatTimer?: ReturnType<typeof setInterval>;
  unsubscribe?: () => void;
}

const connections = new Map<WebSocket, StreamConnection>();

function startHeartbeat(conn: StreamConnection): void {
  conn.heartbeatTimer = setInterval(() => {
    if (conn.missedPings >= MAX_MISSED_PINGS) {
      conn.socket.close(4000, "heartbeat timeout");
      return;
    }
    conn.missedPings += 1;
    if (conn.socket.readyState === conn.socket.OPEN) {
      conn.socket.ping();
    }
  }, HEARTBEAT_MS);
}

function cleanup(conn: StreamConnection): void {
  if (conn.heartbeatTimer) clearInterval(conn.heartbeatTimer);
  conn.unsubscribe?.();
}

export async function registerWebSocket(app: FastifyInstance): Promise<void> {
  app.get("/v1/context/stream", { websocket: true }, async (socket, request) => {
    const token =
      (request.query as { token?: string }).token ??
      new URL(request.url, "http://localhost").searchParams.get("token");

    if (!token) {
      socket.close(4001, "Missing token query parameter");
      return;
    }

    let uid: string;
    try {
      const user = await verifyTokenString(token);
      uid = user.uid;
    } catch {
      socket.close(4001, "Invalid or expired Firebase token");
      return;
    }

    const conn: StreamConnection = {
      socket,
      uid,
      missedPings: 0,
    };
    connections.set(socket, conn);

    conn.unsubscribe = watchUserSnapshots(uid, (snapshotId, status) => {
      if (status === "ready" && socket.readyState === socket.OPEN) {
        socket.send(
          JSON.stringify({
            type: "context_ready",
            snapshotId,
          })
        );
      }
    });

    startHeartbeat(conn);

    socket.on("pong", () => {
      conn.missedPings = 0;
    });

    socket.on("close", () => {
      cleanup(conn);
      connections.delete(socket);
    });

    socket.send(
      JSON.stringify({ type: "connected", uid })
    );
  });
}
