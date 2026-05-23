variable "project_id" { type = string }
variable "location_id" { type = string }
variable "database_id" { type = string }

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = var.database_id
  location_id = var.location_id
  type        = "FIRESTORE_NATIVE"
}

output "database_id" {
  value = google_firestore_database.default.name
}
