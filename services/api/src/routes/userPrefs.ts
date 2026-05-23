import type { FastifyInstance } from "fastify";
import { firestore } from "../lib/firebase.js";

interface PrefsBody {
  geminiApiKey?: string;
  googleCloudApiKey?: string;
  openaiApiKey?: string;
  excludePathsRaw?: string;
  targetToolsRaw?: string;
  redactKeys?: boolean;
  localOnly?: boolean;
  capturingEnabled?: boolean;
  agentEnabled?: boolean;
  geminiModel?: string;
  activeWorkspace?: string;
  confirmEveryAction?: boolean;
  restrictToWorkspace?: boolean;
  launchColorHex?: string;
  hotkeyKeyCode?: number;
  hotkeyModifiers?: number;
  showInNotch?: boolean;
  onboardingComplete?: boolean;
}

export async function userPrefsRoutes(app: FastifyInstance) {
  // GET /v1/user/prefs → returns the user's saved prefs doc (or {} if none).
  app.get("/user/prefs", async (req) => {
    const uid = req.uid!;
    const doc = await firestore()
      .collection("users")
      .doc(uid)
      .collection("config")
      .doc("prefs")
      .get();
    return doc.exists ? doc.data() : {};
  });

  // PUT /v1/user/prefs — partial merge.
  app.put<{ Body: PrefsBody }>("/user/prefs", async (req) => {
    const uid = req.uid!;
    const body = req.body ?? {};
    // Strip undefined keys so partial updates don't blank fields.
    const clean: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(body)) {
      if (v !== undefined) clean[k] = v;
    }
    clean.updatedAt = new Date();
    await firestore()
      .collection("users")
      .doc(uid)
      .collection("config")
      .doc("prefs")
      .set(clean, { merge: true });
    return { ok: true };
  });
}
