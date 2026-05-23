output "api_url" {
  description = "Public Cloud Run URL for the Ithuriel API."
  value       = google_cloud_run_v2_service.api.uri
}

output "api_service_account" {
  description = "Service account email used by the API."
  value       = google_service_account.api.email
}

output "processor_service_account" {
  description = "Service account email used by the snapshot processor."
  value       = google_service_account.processor.email
}

output "artifact_registry" {
  description = "Artifact Registry repository for Docker images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}

output "snapshots_topic" {
  value = google_pubsub_topic.snapshots.id
}

output "snapshots_bucket" {
  value = google_storage_bucket.snapshots.name
}
