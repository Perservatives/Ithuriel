import { Storage } from "@google-cloud/storage";

const storage = new Storage({
  projectId: process.env.GOOGLE_CLOUD_PROJECT,
});

const bucketName =
  process.env.GCS_SNAPSHOTS_BUCKET ?? process.env.SNAPSHOTS_BUCKET ?? "ithuriel-snapshots";

function getBucket() {
  return storage.bucket(bucketName);
}

export function rawSnapshotPath(uid: string, snapshotId: string): string {
  return `snapshots/${uid}/${snapshotId}/raw.json`;
}

export interface RawSnapshotPayload {
  source: string;
  activeFiles: string[];
  recentEdits: string[];
  terminalHistory: string[];
  gitBranch: string;
  gitCommit: string;
  rawContent: string;
}

export async function uploadRawSnapshot(
  uid: string,
  snapshotId: string,
  payload: RawSnapshotPayload
): Promise<string> {
  const path = rawSnapshotPath(uid, snapshotId);
  const file = getBucket().file(path);
  await file.save(JSON.stringify(payload), {
    contentType: "application/json",
    metadata: {
      metadata: {
        uid,
        snapshotId,
      },
    },
  });
  return `gs://${bucketName}/${path}`;
}

export async function getSignedReadUrl(
  gcsUri: string,
  expiresMinutes = 15
): Promise<string> {
  const match = gcsUri.match(/^gs:\/\/([^/]+)\/(.+)$/);
  if (!match) {
    throw new Error(`Invalid GCS URI: ${gcsUri}`);
  }
  const [, bucket, objectPath] = match;
  const [url] = await storage
    .bucket(bucket)
    .file(objectPath)
    .getSignedUrl({
      action: "read",
      expires: Date.now() + expiresMinutes * 60 * 1000,
    });
  return url;
}

export { bucketName, storage };
