/**
 * Vertex AI text-embedding-005 helper. Returns a 768-dim vector for a single
 * piece of text. Uses google-auth-library's application-default credentials
 * available to the Cloud Run service account.
 */
import { GoogleAuth } from "google-auth-library";

const PROJECT  = process.env.GCP_PROJECT ?? "";
const LOCATION = process.env.VERTEX_REGION ?? "us-central1";
const MODEL    = "text-embedding-005";

let authClient: GoogleAuth | null = null;
function auth(): GoogleAuth {
  authClient ??= new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  return authClient;
}

export async function embed(text: string): Promise<number[]> {
  const client = await auth().getClient();
  const token  = (await client.getAccessToken()).token;
  const url    = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}:predict`;

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      instances: [{ content: text.slice(0, 8000), task_type: "RETRIEVAL_QUERY" }],
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`vertex ${resp.status}: ${body.slice(0, 200)}`);
  }
  const json = (await resp.json()) as {
    predictions?: Array<{ embeddings?: { values?: number[] } }>;
  };
  const vec = json.predictions?.[0]?.embeddings?.values;
  if (!vec) throw new Error("vertex returned no embedding");
  return vec;
}

export function cosine(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    dot += av * bv;
    na  += av * av;
    nb  += bv * bv;
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}
