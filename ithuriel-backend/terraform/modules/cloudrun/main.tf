variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "api_image" { type = string }
variable "dashboard_image" { type = string }
variable "api_service_account" { type = string }
variable "snapshots_bucket" { type = string }
variable "snapshots_topic" { type = string }
variable "processed_topic" { type = string }
variable "firebase_project_id" { type = string }
variable "labels" { type = map(string) }

resource "google_cloud_run_v2_service" "api" {
  name     = "${var.name_prefix}-api"
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  labels = var.labels

  template {
    service_account = var.api_service_account

    containers {
      image = var.api_image

      ports {
        container_port = 8080
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GCS_SNAPSHOTS_BUCKET"
        value = var.snapshots_bucket
      }
      env {
        name  = "PUBSUB_SNAPSHOTS_TOPIC"
        value = var.snapshots_topic
      }
      env {
        name  = "FIREBASE_PROJECT_ID"
        value = var.firebase_project_id
      }
      env {
        name  = "LOG_LEVEL"
        value = "info"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 20
    }
  }
}

resource "google_cloud_run_v2_service" "dashboard" {
  count    = var.dashboard_image != "" ? 1 : 0
  name     = "${var.name_prefix}-dashboard"
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  labels = var.labels

  template {
    containers {
      image = var.dashboard_image

      ports {
        container_port = 3000
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "api_service_uri" {
  value = google_cloud_run_v2_service.api.uri
}

output "dashboard_service_uri" {
  value = length(google_cloud_run_v2_service.dashboard) > 0 ? google_cloud_run_v2_service.dashboard[0].uri : ""
}
