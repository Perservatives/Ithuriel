import { PubSub } from "@google-cloud/pubsub";

const client = new PubSub({ projectId: process.env.GCP_PROJECT });

export async function publish(topicName: string, payload: object): Promise<string> {
  const topic = client.topic(topicName);
  const data = Buffer.from(JSON.stringify(payload));
  return topic.publishMessage({ data });
}
