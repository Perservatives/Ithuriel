import { PubSub } from "@google-cloud/pubsub";

const pubsub = new PubSub({
  projectId: process.env.GOOGLE_CLOUD_PROJECT,
  apiEndpoint: process.env.PUBSUB_EMULATOR_HOST,
});

const SNAPSHOTS_TOPIC =
  process.env.PUBSUB_SNAPSHOTS_TOPIC ?? "ithuriel-snapshots";

export interface SnapshotMessage {
  uid: string;
  snapshotId: string;
  rawRef: string;
}

export async function publishSnapshotForProcessing(
  message: SnapshotMessage
): Promise<string> {
  const topic = pubsub.topic(SNAPSHOTS_TOPIC);
  const data = Buffer.from(JSON.stringify(message));
  const messageId = await topic.publishMessage({ data });
  return messageId;
}

export { pubsub, SNAPSHOTS_TOPIC };
