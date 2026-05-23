import type { FastifyInstance } from "fastify";
import { auth, firestore } from "../lib/firebase.js";

/**
 * OAuth bridge for the macOS app. The native client opens
 *   <API_URL>/auth/google?redirect=ithuriel://auth/callback
 * in the system browser. We forward to Google's OAuth, exchange the code
 * for an ID token, mint a Firebase custom token, then redirect back to the
 * app via its registered URL scheme.
 *
 * The macOS app exchanges the custom token for an ID token using the
 * Firebase REST endpoint signInWithCustomToken, then uses that ID token
 * as Bearer for all /v1 calls.
 */
const CLIENT_ID     = process.env.OAUTH_CLIENT_ID     ?? "";
const CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET ?? "";
const GOOGLE_AUTH   = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN  = "https://oauth2.googleapis.com/token";
const GOOGLE_USER   = "https://www.googleapis.com/oauth2/v3/userinfo";

export async function authBridgeRoutes(app: FastifyInstance) {
  app.get<{ Querystring: { redirect?: string } }>("/auth/google", async (req, reply) => {
    const redirect = req.query.redirect ?? "ithuriel://auth/callback";
    const state    = Buffer.from(JSON.stringify({ redirect })).toString("base64url");
    const url = new URL(GOOGLE_AUTH);
    url.searchParams.set("client_id", CLIENT_ID);
    url.searchParams.set("redirect_uri", `${requestBaseURL(req)}/auth/callback`);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("scope", "openid email profile");
    url.searchParams.set("state", state);
    url.searchParams.set("access_type", "online");
    url.searchParams.set("prompt", "select_account");
    return reply.redirect(url.toString());
  });

  app.get<{ Querystring: { code?: string; state?: string } }>("/auth/callback", async (req, reply) => {
    const { code, state } = req.query;
    if (!code) return reply.code(400).send({ error: "missing code" });

    const tokenBody = new URLSearchParams({
      code,
      client_id:     CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri:  `${requestBaseURL(req)}/auth/callback`,
      grant_type:    "authorization_code",
    });

    const tokRes = await fetch(GOOGLE_TOKEN, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenBody.toString(),
    });
    if (!tokRes.ok) {
      const txt = await tokRes.text();
      return reply.code(502).send({ error: "google token exchange failed", detail: txt.slice(0, 200) });
    }
    const tok = (await tokRes.json()) as { access_token: string };

    const userRes = await fetch(GOOGLE_USER, {
      headers: { Authorization: `Bearer ${tok.access_token}` },
    });
    if (!userRes.ok) return reply.code(502).send({ error: "userinfo failed" });
    const user = (await userRes.json()) as { sub: string; email?: string; name?: string };

    // Upsert into Firebase Auth + Firestore.
    const uid = `google_${user.sub}`;
    try { await auth().getUser(uid); }
    catch {
      await auth().createUser({
        uid,
        email: user.email,
        displayName: user.name,
      });
    }
    await firestore().collection("users").doc(uid).set({
      uid,
      email: user.email ?? null,
      displayName: user.name ?? null,
      lastSignInAt: new Date(),
    }, { merge: true });

    const customToken = await auth().createCustomToken(uid, { provider: "google" });

    const redirect = decodeState(state) ?? "ithuriel://auth/callback";
    const finalURL = `${redirect}?token=${encodeURIComponent(customToken)}`;
    return reply.redirect(finalURL);
  });
}

function decodeState(state?: string): string | null {
  if (!state) return null;
  try { return (JSON.parse(Buffer.from(state, "base64url").toString()) as { redirect: string }).redirect; }
  catch { return null; }
}

function requestBaseURL(req: any): string {
  const proto = req.headers["x-forwarded-proto"] ?? "https";
  const host  = req.headers["x-forwarded-host"]  ?? req.headers.host;
  return `${proto}://${host}`;
}
