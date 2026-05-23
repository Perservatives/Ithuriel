resource "google_secret_manager_secret" "gemini_key" {
  secret_id  = "ithuriel-gemini-key"
  replication { auto {} }
  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "gemini_key" {
  count       = var.gemini_api_key == "" ? 0 : 1
  secret      = google_secret_manager_secret.gemini_key.id
  secret_data = var.gemini_api_key
}

resource "google_secret_manager_secret" "oauth_client_id" {
  secret_id  = "ithuriel-oauth-client-id"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "oauth_client_id" {
  secret      = google_secret_manager_secret.oauth_client_id.id
  secret_data = var.oauth_client_id
}

resource "google_secret_manager_secret" "oauth_client_secret" {
  secret_id  = "ithuriel-oauth-client-secret"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "oauth_client_secret" {
  secret      = google_secret_manager_secret.oauth_client_secret.id
  secret_data = var.oauth_client_secret
}
