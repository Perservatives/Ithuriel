resource "google_firestore_database" "default" {
  provider                          = google-beta
  project                           = var.project_id
  name                              = "(default)"
  location_id                       = var.region
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.enabled]
}

# Composite indexes needed by the API for snapshot/run pagination by user.
resource "google_firestore_index" "snapshots_by_user_time" {
  project    = var.project_id
  database   = google_firestore_database.default.name
  collection = "snapshots"

  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  fields {
    field_path = "capturedAt"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "agent_runs_by_user_time" {
  project    = var.project_id
  database   = google_firestore_database.default.name
  collection = "agentRuns"

  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  fields {
    field_path = "startedAt"
    order      = "DESCENDING"
  }
}
