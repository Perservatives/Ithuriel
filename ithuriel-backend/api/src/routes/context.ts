import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { v4 as uuidv4 } from "uuid";
import { verifyFirebaseToken } from "../auth.js";
import { redactSnapshotFields } from "../redact.js";
import type { ContextFormat } from "../models.js";
import {
  createSnapshotMetadata,
  getLatestProcessedSnapshot,
  getSnapshot,
  listSnapshots,
} from "../services/firestore.js";
import { formatSnapshot, toFormattable } from "../services/formatter.js";
import { publishSnapshotForProcessing } from "../services/pubsub.js";
import { uploadRawSnapshot } from "../services/storage.js";
import { Timestamp } from "@google-cloud/firestore";

const MAX_RAW_BYTES = 500 * 1024;

const snapshotBodySchema = z.object({
  source: z.string().min(1).max(256),
  activeFiles: z.array(z.string().max(1024)).max(200).default([]),
  recentEdits: z.array(z.string().max(4096)).max(100).default([]),
  terminalHistory: z.array(z.string().max(8192)).max(50).default([]),
  gitBranch: z.string().max(256).default(""),
  gitCommit: z.string().max(64).default(""),
  rawContent: z.string().max(MAX_RAW_BYTES),
});

const formatSchema = z.enum(["claude", "cursor", "chatgpt", "copilot"]);

const injectBodySchema = z.object({
  snapshotId: z.string().uuid().optional(),
  format: formatSchema,
});

export async function contextRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", async (request, reply) => {
    if (
      request.routerPath?.startsWith("/v1/context") &&
      request.routerPath !== "/v1/context/stream"
    ) {
      await verifyFirebaseToken(request, reply);
    }
  });

  app.post("/v1/context/snapshot", async (request, reply) => {
    const parsed = snapshotBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "ValidationError",
        details: parsed.error.flatten(),
      });
    }

    const rawBytes = Buffer.byteLength(parsed.data.rawContent, "utf8");
    if (rawBytes > MAX_RAW_BYTES) {
      return reply.code(400).send({
        error: "ValidationError",
        message: `rawContent exceeds ${MAX_RAW_BYTES} bytes`,
      });
    }

    const uid = request.user!.uid;
    const snapshotId = uuidv4();
    const redacted = redactSnapshotFields(parsed.data);

    const rawRef = await uploadRawSnapshot(uid, snapshotId, redacted);

    await createSnapshotMetadata({
      uid,
      snapshotId,
      source: redacted.source,
      activeFiles: redacted.activeFiles,
      recentEdits: redacted.recentEdits,
      terminalHistory: redacted.terminalHistory,
      gitBranch: redacted.gitBranch,
      gitCommit: redacted.gitCommit,
      rawRef,
    });

    await publishSnapshotForProcessing({ uid, snapshotId, rawRef });

    return reply.code(202).send({
      snapshotId,
      status: "processing" as const,
    });
  });

  app.get<{ Querystring: { format?: string } }>(
    "/v1/context/current",
    async (request, reply) => {
      const formatResult = formatSchema.safeParse(
        request.query.format ?? "claude"
      );
      if (!formatResult.success) {
        return reply.code(400).send({
          error: "ValidationError",
          message: "format must be claude|cursor|chatgpt|copilot",
        });
      }

      const uid = request.user!.uid;
      const latest = await getLatestProcessedSnapshot(uid);
      if (!latest) {
        return reply.code(404).send({
          error: "NotFound",
          message: "No processed context available",
        });
      }

      const format = formatResult.data as ContextFormat;
      const capturedAt = (latest.capturedAt as Timestamp)
        .toDate()
        .toISOString();

      return {
        snapshotId: latest.id,
        format,
        context: formatSnapshot(latest, format),
        capturedAt,
      };
    }
  );

  app.get<{ Querystring: { limit?: string; cursor?: string } }>(
    "/v1/context/history",
    async (request, reply) => {
      const limit = Math.min(
        Math.max(parseInt(request.query.limit ?? "20", 10) || 20, 1),
        100
      );
      const uid = request.user!.uid;
      const { items, nextCursor } = await listSnapshots(
        uid,
        limit,
        request.query.cursor
      );

      return {
        items,
        nextCursor: nextCursor ?? null,
      };
    }
  );

  app.get<{ Params: { id: string } }>("/v1/context/:id", async (request, reply) => {
    const uid = request.user!.uid;
    const snapshot = await getSnapshot(uid, request.params.id);

    if (!snapshot) {
      return reply.code(404).send({
        error: "NotFound",
        message: "Snapshot not found",
      });
    }

    const capturedAt = (snapshot.capturedAt as Timestamp)
      .toDate()
      .toISOString();
    const processedAt = snapshot.processedAt
      ? (snapshot.processedAt as Timestamp).toDate().toISOString()
      : undefined;

    return {
      ...snapshot,
      capturedAt,
      processedAt,
    };
  });

  app.post("/v1/context/inject", async (request, reply) => {
    const parsed = injectBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "ValidationError",
        details: parsed.error.flatten(),
      });
    }

    const uid = request.user!.uid;
    const format = parsed.data.format;

    let meta;
    if (parsed.data.snapshotId) {
      meta = await getSnapshot(uid, parsed.data.snapshotId);
      if (!meta) {
        return reply.code(404).send({
          error: "NotFound",
          message: "Snapshot not found",
        });
      }
    } else {
      meta = await getLatestProcessedSnapshot(uid);
      if (!meta) {
        return reply.code(404).send({
          error: "NotFound",
          message: "No processed context available",
        });
      }
    }

    const formattable = toFormattable(meta);
    if (!formattable) {
      return reply.code(409).send({
        error: "Conflict",
        message: "Snapshot is still processing",
        snapshotId: meta.id,
        status: meta.status,
      });
    }

    const capturedAt = (meta.capturedAt as Timestamp).toDate().toISOString();

    return {
      snapshotId: meta.id,
      format,
      context: formatSnapshot(formattable, format),
      capturedAt,
    };
  });
}
