terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Configure per environment:
    # terraform init -backend-config=environments/dev.backend.hcl
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name_prefix = "ithuriel-${var.environment}"
  common_labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
    app         = "ithuriel"
  })
  firebase_project = var.firebase_project_id != "" ? var.firebase_project_id : var.project_id
}

resource "google_service_account" "api_sa" {
  account_id   = "${local.name_prefix}-api"
  display_name = "Ithuriel API (${var.environment})"
}

resource "google_service_account" "processor_sa" {
  account_id   = "${local.name_prefix}-processor"
  display_name = "Ithuriel Processor (${var.environment})"
}

resource "google_service_account" "cicd_sa" {
  account_id   = "${local.name_prefix}-cicd"
  display_name = "Ithuriel CI/CD (${var.environment})"
}

module "firestore" {
  source      = "./modules/firestore"
  project_id  = var.project_id
  location_id = var.region
  database_id = "(default)"
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  region      = var.region
  bucket_name = "${local.name_prefix}-snapshots"
  labels      = local.common_labels
}

module "pubsub" {
  source         = "./modules/pubsub"
  project_id     = var.project_id
  name_prefix    = local.name_prefix
  processor_sa   = google_service_account.processor_sa.email
  dead_letter_sa = google_service_account.processor_sa.email
}

module "functions" {
  source                = "./modules/functions"
  project_id            = var.project_id
  region                = var.region
  name_prefix           = local.name_prefix
  service_account_email = google_service_account.processor_sa.email
  source_bucket         = var.processor_source_bucket
  source_object         = var.processor_source_object
  snapshots_topic_id    = module.pubsub.snapshots_topic_id
  processed_topic_id    = module.pubsub.processed_topic_id
  snapshots_bucket      = module.storage.bucket_name
  labels                = local.common_labels
  depends_on = [
    module.pubsub,
    module.storage,
  ]
}

module "cloudrun" {
  source                = "./modules/cloudrun"
  project_id            = var.project_id
  region                = var.region
  name_prefix           = local.name_prefix
  api_image             = var.api_image
  dashboard_image       = var.dashboard_image
  api_service_account   = google_service_account.api_sa.email
  snapshots_bucket      = module.storage.bucket_name
  snapshots_topic       = module.pubsub.snapshots_topic_id
  processed_topic       = module.pubsub.processed_topic_id
  firebase_project_id   = local.firebase_project
  labels                = local.common_labels
}

resource "google_secret_manager_secret" "vertex_key" {
  secret_id = "${local.name_prefix}-vertex-key"
  replication {
    auto {}
  }
  labels = local.common_labels
}

resource "google_secret_manager_secret" "github_oauth" {
  secret_id = "${local.name_prefix}-github-oauth-secret"
  replication {
    auto {}
  }
  labels = local.common_labels
}

# --- API service account IAM ---
resource "google_project_iam_member" "api_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_storage_bucket_iam_member" "api_storage" {
  bucket = module.storage.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_pubsub_topic_iam_member" "api_publish_snapshots" {
  topic  = module.pubsub.snapshots_topic_id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_token_verifier" {
  project = var.project_id
  role    = "roles/firebaseauth.admin"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

# --- Processor service account IAM ---
resource "google_project_iam_member" "processor_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.processor_sa.email}"
}

resource "google_storage_bucket_iam_member" "processor_storage" {
  bucket = module.storage.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.processor_sa.email}"
}

resource "google_pubsub_topic_iam_member" "processor_publish_processed" {
  topic  = module.pubsub.processed_topic_id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.processor_sa.email}"
}

resource "google_project_iam_member" "processor_vertex" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.processor_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "processor_vertex_secret" {
  secret_id = google_secret_manager_secret.vertex_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.processor_sa.email}"
}

# --- CI/CD service account IAM ---
resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cicd_sa.email}"
}

resource "google_project_iam_member" "cicd_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd_sa.email}"
}

resource "google_project_iam_member" "cicd_functions_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.cicd_sa.email}"
}
