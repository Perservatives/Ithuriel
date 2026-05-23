import { Storage } from "@google-cloud/storage";

const storage = new Storage({ projectId: process.env.GCP_PROJECT });

export async function writeJSON(bucket: string, path: string, payload: object): Promise<string> {
  const file = storage.bucket(bucket).file(path);
  await file.save(JSON.stringify(payload), {
    contentType: "application/json",
    resumable: false,
  });
  return `gs://${bucket}/${path}`;
}

export async function signedReadURL(bucket: string, path: string, ttlSec = 300): Promise<string> {
  const [url] = await storage.bucket(bucket).file(path).getSignedUrl({
    action: "read",
    expires: Date.now() + ttlSec * 1000,
    version: "v4",
  });
  return url;
}
