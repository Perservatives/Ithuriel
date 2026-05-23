resource "google_storage_bucket" "snapshots" {
  name                        = "${var.project_id}-ithuriel-snapshots"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    condition { age = 90 }
    action    { type = "Delete" }
  }

  versioning { enabled = false }
  public_access_prevention = "enforced"

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket" "screenshots" {
  name                        = "${var.project_id}-ithuriel-screenshots"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    condition { age = 30 }
    action    { type = "Delete" }
  }

  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-ithuriel-functions"
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_artifact_registry_repository" "containers" {
  provider      = google-beta
  location      = var.region
  repository_id = "ithuriel"
  format        = "DOCKER"
  depends_on    = [google_project_service.enabled]
}
