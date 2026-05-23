import { Firestore, FieldValue, Timestamp } from "@google-cloud/firestore";
import type {
  ProcessedSnapshot,
  SnapshotListItem,
  SnapshotMetadata,
  SnapshotStatus,
} from "../models.js";

const db = new Firestore({
  projectId: process.env.GOOGLE_CLOUD_PROJECT,
});

const snapshotsCol = (uid: string) =>
  db.collection("users").doc(uid).collection("snapshots");

export interface CreateSnapshotInput {
  uid: string;
  snapshotId: string;
  source: string;
  activeFiles: string[];
  recentEdits: string[];
  terminalHistory: string[];
  gitBranch: string;
  gitCommit: string;
  rawRef: string;
}

export async function createSnapshotMetadata(
  input: CreateSnapshotInput
): Promise<SnapshotMetadata> {
  const ref = snapshotsCol(input.uid).doc(input.snapshotId);
  const capturedAt = Timestamp.now();
  const doc: Omit<SnapshotMetadata, "id"> = {
    uid: input.uid,
    source: input.source,
    activeFiles: input.activeFiles,
    recentEdits: input.recentEdits,
    terminalHistory: input.terminalHistory,
    gitBranch: input.gitBranch,
    gitCommit: input.gitCommit,
    rawRef: input.rawRef,
    status: "processing",
    capturedAt,
  };

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      throw new Error("Snapshot ID collision");
    }
    tx.set(ref, doc);
  });

  return { id: input.snapshotId, ...doc };
}

export async function getSnapshot(
  uid: string,
  snapshotId: string
): Promise<SnapshotMetadata | null> {
  const snap = await snapshotsCol(uid).doc(snapshotId).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...(snap.data() as Omit<SnapshotMetadata, "id">) };
}

export async function getLatestProcessedSnapshot(
  uid: string
): Promise<ProcessedSnapshot | null> {
  const query = await snapshotsCol(uid)
    .where("status", "==", "ready")
    .orderBy("capturedAt", "desc")
    .limit(1)
    .get();

  if (query.empty) return null;
  const doc = query.docs[0];
  const data = doc.data() as Omit<SnapshotMetadata, "id">;
  return {
    id: doc.id,
    ...data,
    status: "ready",
    summaryFull: data.summaryFull ?? "",
  } as ProcessedSnapshot;
}

export async function listSnapshots(
  uid: string,
  limit: number,
  cursorId?: string
): Promise<{ items: SnapshotListItem[]; nextCursor?: string }> {
  let query = snapshotsCol(uid)
    .orderBy("capturedAt", "desc")
    .limit(limit + 1);

  if (cursorId) {
    const cursorDoc = await snapshotsCol(uid).doc(cursorId).get();
    if (cursorDoc.exists) {
      query = query.startAfter(cursorDoc);
    }
  }

  const snapshot = await query.get();
  const docs = snapshot.docs;
  const hasMore = docs.length > limit;
  const page = hasMore ? docs.slice(0, limit) : docs;

  const items: SnapshotListItem[] = page.map((doc) => {
    const d = doc.data();
    const capturedAt = d.capturedAt as Timestamp;
    return {
      id: doc.id,
      capturedAt: capturedAt.toDate().toISOString(),
      source: d.source as string,
      gitBranch: d.gitBranch as string,
    };
  });

  return {
    items,
    nextCursor: hasMore ? page[page.length - 1].id : undefined,
  };
}

export function watchUserSnapshots(
  uid: string,
  onUpdate: (snapshotId: string, status: SnapshotStatus) => void
): () => void {
  const unsubscribe = snapshotsCol(uid)
    .where("status", "in", ["ready", "error"])
    .onSnapshot((snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type === "added" || change.type === "modified") {
          const data = change.doc.data();
          onUpdate(change.doc.id, data.status as SnapshotStatus);
        }
      });
    });

  return unsubscribe;
}

export { db, FieldValue, Timestamp };
