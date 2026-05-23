variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "service_account_email" { type = string }
variable "source_bucket" { type = string }
variable "source_object" { type = string }
variable "snapshots_topic_id" { type = string }
variable "processed_topic_id" { type = string }
variable "snapshots_bucket" { type = string }
variable "labels" { type = map(string) }

resource "google_cloudfunctions2_function" "processor" {
  name        = "${var.name_prefix}-processor"
  location    = var.region
  project     = var.project_id
  description = "Processes Ithuriel context snapshots via Vertex AI"

  labels = var.labels

  build_config {
    runtime     = "python312"
    entry_point = "process_snapshot"
    source {
      storage_source {
        bucket = var.source_bucket
        object = var.source_object
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "1Gi"
    timeout_seconds       = 540
    service_account_email = var.service_account_email

    environment_variables = {
      GOOGLE_CLOUD_PROJECT    = var.project_id
      GCS_SNAPSHOTS_BUCKET    = var.snapshots_bucket
      PUBSUB_PROCESSED_TOPIC  = replace(var.processed_topic_id, "projects/${var.project_id}/topics/", "")
      VERTEX_LOCATION         = var.region
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = "projects/${var.project_id}/topics/${var.snapshots_topic_id}"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = var.service_account_email
  }
}

# Eventarc-managed subscription is named by GCP; processor-sub is the logical name in docs.

output "function_name" {
  value = google_cloudfunctions2_function.processor.name
}

output "function_uri" {
  value = google_cloudfunctions2_function.processor.service_config[0].uri
}
