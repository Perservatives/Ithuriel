import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";

/**
 * Pushes Firestore snapshot writes to the connected client in real time.
 * The client subscribes after auth via /v1/context/stream.
 */
export async function streamRoutes(app: FastifyInstance) {
  app.get("/context/stream", { websocket: true }, (connection, req) => {
    const uid = (req as any).uid as string | undefined;
    if (!uid) {
      connection.socket.send(JSON.stringify({ error: "unauthorized" }));
      connection.socket.close();
      return;
    }

    const unsubscribe = firestore()
      .collection("snapshots")
      .where("userId", "==", uid)
      .orderBy("capturedAt", "desc")
      .limit(1)
      .onSnapshot(
        (snap) => {
          for (const change of snap.docChanges()) {
            if (change.type === "added" || change.type === "modified") {
              connection.socket.send(JSON.stringify(change.doc.data()));
            }
          }
        },
        (err) => {
          connection.socket.send(JSON.stringify({ error: err.message }));
        },
      );

    connection.socket.on("close", () => unsubscribe());
  });
}
