import admin from "firebase-admin";

let app: admin.app.App | null = null;

export function initFirebase(): admin.app.App {
  if (app) return app;
  app = admin.initializeApp({
    projectId: process.env.GCP_PROJECT,
  });
  return app;
}

export function auth() {
  return initFirebase().auth();
}

export function firestore() {
  return initFirebase().firestore();
}
