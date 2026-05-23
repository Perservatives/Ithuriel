import type { DecodedIdToken } from "firebase-admin/auth";

export type ContextFormat = "claude" | "cursor" | "chatgpt" | "copilot";

export type SnapshotStatus = "processing" | "ready" | "error";

export interface SnapshotMetadata {
  id: string;
  uid: string;
  source: string;
  activeFiles: string[];
  recentEdits: string[];
  terminalHistory: string[];
  gitBranch: string;
  gitCommit: string;
  rawRef: string;
  status: SnapshotStatus;
  capturedAt: FirebaseFirestore.Timestamp;
  processedAt?: FirebaseFirestore.Timestamp;
  summaryShort?: string;
  summaryMedium?: string;
  summaryFull?: string;
  embedding?: number[];
  error?: string;
}

export interface ProcessedSnapshot extends SnapshotMetadata {
  status: "ready";
  summaryFull: string;
}

export interface AuthUser {
  uid: string;
  email?: string;
}

declare module "fastify" {
  interface FastifyRequest {
    user?: AuthUser;
    token?: DecodedIdToken;
  }
}

export interface SnapshotListItem {
  id: string;
  capturedAt: string;
  source: string;
  gitBranch: string;
}

export interface InjectPayload {
  snapshotId: string;
  format: ContextFormat;
  context: string;
  capturedAt: string;
}
