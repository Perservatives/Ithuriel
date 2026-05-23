data "archive_file" "processor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../services/functions/processor"
  output_path = "${path.module}/.build/processor.zip"
}

resource "google_storage_bucket_object" "processor_source" {
  name   = "processor-${data.archive_file.processor_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.processor_zip.output_path
}

resource "google_cloudfunctions2_function" "processor" {
  name        = "ithuriel-processor"
  location    = var.region
  description = "Processes new ContextSnapshots: Vertex AI embeddings + Firestore writes."

  build_config {
    runtime     = "python312"
    entry_point = "handle"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.processor_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 50
    available_memory      = "1Gi"
    timeout_seconds       = 120
    service_account_email = google_service_account.processor.email
    environment_variables = {
      GCP_PROJECT             = var.project_id
      GCS_BUCKET_SNAPSHOTS    = google_storage_bucket.snapshots.name
      VERTEX_REGION           = var.region
      PROCESSED_TOPIC         = google_pubsub_topic.processed.name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.snapshots.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [google_project_service.enabled, google_project_iam_member.processor]
}
