variable "project_id" { type = string }
variable "name_prefix" { type = string }
variable "processor_sa" { type = string }
variable "dead_letter_sa" { type = string }

resource "google_pubsub_topic" "snapshots" {
  name    = "ithuriel-snapshots"
  project = var.project_id

  message_retention_duration = "86400s"
}

resource "google_pubsub_topic" "processed" {
  name    = "ithuriel-processed"
  project = var.project_id
}

resource "google_pubsub_topic" "dead_letter" {
  name    = "${var.name_prefix}-snapshots-dlq"
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.dead_letter.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${var.dead_letter_sa}"
}

output "snapshots_topic_id" {
  value = google_pubsub_topic.snapshots.name
}

output "processed_topic_id" {
  value = google_pubsub_topic.processed.name
}

output "dead_letter_topic_id" {
  value = google_pubsub_topic.dead_letter.name
}
