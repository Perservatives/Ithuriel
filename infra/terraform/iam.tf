resource "google_service_account" "api" {
  account_id   = "ithuriel-api"
  display_name = "Ithuriel Cloud Run API"
  depends_on   = [google_project_service.enabled]
}

resource "google_service_account" "processor" {
  account_id   = "ithuriel-processor"
  display_name = "Ithuriel Pub/Sub → Vertex AI processor"
  depends_on   = [google_project_service.enabled]
}

# API service can: read/write Firestore, publish to Pub/Sub, sign GCS URLs,
# read Secret Manager, call Vertex AI, mint custom Firebase tokens.
locals {
  api_roles = [
    "roles/datastore.user",
    "roles/pubsub.publisher",
    "roles/storage.objectAdmin",
    "roles/secretmanager.secretAccessor",
    "roles/aiplatform.user",
    "roles/firebaseauth.admin",
    "roles/iam.serviceAccountTokenCreator"
  ]
  processor_roles = [
    "roles/datastore.user",
    "roles/storage.objectAdmin",
    "roles/secretmanager.secretAccessor",
    "roles/aiplatform.user",
    "roles/pubsub.subscriber"
  ]
}

resource "google_project_iam_member" "api" {
  for_each = toset(local.api_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "processor" {
  for_each = toset(local.processor_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.processor.email}"
}
