/**
 * Optional server-side Gemini proxy. Lets premium users run the agent
 * without supplying their own key. Calls the public Generative Language
 * API (v1beta) with the GEMINI_API_KEY secret.
 */
const KEY = process.env.GEMINI_API_KEY;

export async function generateContent(model: string, body: unknown): Promise<unknown> {
  if (!KEY) throw new Error("server-side Gemini key not configured");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`gemini ${resp.status}: ${txt.slice(0, 300)}`);
  }
  return resp.json();
}
