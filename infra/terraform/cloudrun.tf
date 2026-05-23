resource "google_cloud_run_v2_service" "api" {
  name     = "ithuriel-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.api.email
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      image = var.api_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "PUBSUB_TOPIC_SNAPSHOTS"
        value = google_pubsub_topic.snapshots.name
      }
      env {
        name  = "PUBSUB_TOPIC_AGENT_RUNS"
        value = google_pubsub_topic.agent_runs.name
      }
      env {
        name  = "PUBSUB_TOPIC_TEAM"
        value = google_pubsub_topic.team_broadcast.name
      }
      env {
        name  = "GCS_BUCKET_SNAPSHOTS"
        value = google_storage_bucket.snapshots.name
      }
      env {
        name  = "GCS_BUCKET_SCREENSHOTS"
        value = google_storage_bucket.screenshots.name
      }
      env {
        name  = "ALLOWED_ORIGINS"
        value = join(",", var.allowed_origins)
      }

      env {
        name = "OAUTH_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.oauth_client_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "OAUTH_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.oauth_client_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [google_project_service.enabled, google_project_iam_member.api]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
