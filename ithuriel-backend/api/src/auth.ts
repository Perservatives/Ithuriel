import type { FastifyReply, FastifyRequest } from "fastify";
import { getAuth } from "firebase-admin/auth";
import { initializeApp, getApps, cert, applicationDefault } from "firebase-admin/app";

function initFirebase(): void {
  if (getApps().length > 0) return;

  const projectId = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.FIREBASE_PROJECT_ID;
  const emulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;

  if (emulatorHost) {
    initializeApp({ projectId: projectId ?? "ithuriel-dev" });
    return;
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_SERVICE_ACCOUNT) {
    const sa = process.env.FIREBASE_SERVICE_ACCOUNT
      ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
      : undefined;
    initializeApp({
      credential: sa ? cert(sa) : applicationDefault(),
      projectId,
    });
    return;
  }

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });
}

initFirebase();

export async function verifyFirebaseToken(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    reply.code(401).send({
      error: "Unauthorized",
      message: "Missing or invalid Authorization header. Expected: Bearer <token>",
    });
    return;
  }

  const token = header.slice(7).trim();
  if (!token) {
    reply.code(401).send({
      error: "Unauthorized",
      message: "Empty bearer token",
    });
    return;
  }

  try {
    const decoded = await getAuth().verifyIdToken(token);
    request.user = {
      uid: decoded.uid,
      email: decoded.email,
    };
    request.token = decoded;
  } catch (err) {
    const message =
      err instanceof Error && err.message.includes("expired")
        ? "Firebase ID token has expired. Please sign in again."
        : "Invalid Firebase ID token. Authentication failed.";

    request.log.warn({ err }, "JWT verification failed");
    reply.code(401).send({
      error: "Unauthorized",
      message,
    });
  }
}

export async function verifyTokenString(token: string): Promise<{
  uid: string;
  email?: string;
}> {
  const decoded = await getAuth().verifyIdToken(token);
  return { uid: decoded.uid, email: decoded.email };
}
