resource "google_pubsub_topic" "snapshots" {
  name       = "ithuriel-snapshots"
  depends_on = [google_project_service.enabled]
}

resource "google_pubsub_topic" "processed" {
  name = "ithuriel-snapshots-processed"
}

resource "google_pubsub_topic" "agent_runs" {
  name = "ithuriel-agent-runs"
}

resource "google_pubsub_topic" "team_broadcast" {
  name = "ithuriel-team-broadcast"
}

# Subscription consumed by the Cloud Function (push via Eventarc).
resource "google_pubsub_subscription" "snapshots_processor" {
  name  = "ithuriel-snapshots-processor"
  topic = google_pubsub_topic.snapshots.name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"   # 7 days
  enable_message_ordering    = false
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}
