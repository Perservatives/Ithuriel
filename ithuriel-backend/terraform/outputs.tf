output "api_url" {
  value       = module.cloudrun.api_service_uri
  description = "Cloud Run API service URL"
}

output "dashboard_url" {
  value       = module.cloudrun.dashboard_service_uri
  description = "Cloud Run Dashboard service URL"
}

output "snapshots_bucket" {
  value       = module.storage.bucket_name
  description = "GCS bucket for raw snapshots"
}

output "firestore_database" {
  value       = module.firestore.database_id
  description = "Firestore database ID"
}

output "snapshots_topic" {
  value       = module.pubsub.snapshots_topic_id
  description = "Pub/Sub topic for incoming snapshots"
}

output "processed_topic" {
  value       = module.pubsub.processed_topic_id
  description = "Pub/Sub topic for processed snapshots"
}

output "processor_function" {
  value       = module.functions.function_name
  description = "Cloud Function name for snapshot processor"
}

output "api_service_account" {
  value       = google_service_account.api_sa.email
  description = "API service account email"
}

output "processor_service_account" {
  value       = google_service_account.processor_sa.email
  description = "Processor service account email"
}
