variable "project_id" { type = string }
variable "region" { type = string }
variable "bucket_name" { type = string }
variable "labels" { type = map(string) }

resource "google_storage_bucket" "snapshots" {
  name     = var.bucket_name
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = false

  labels = var.labels

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = false
  }
}

output "bucket_name" {
  value = google_storage_bucket.snapshots.name
}
