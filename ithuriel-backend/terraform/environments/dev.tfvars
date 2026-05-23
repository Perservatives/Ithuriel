project_id              = "ithuriel-dev"
region                  = "us-central1"
environment             = "dev"
api_image               = "us-central1-docker.pkg.dev/ithuriel-dev/ithuriel/api:latest"
dashboard_image         = ""
processor_source_bucket = "ithuriel-dev-terraform-state"
processor_source_object = "processor/dev.zip"
firebase_project_id     = "ithuriel-dev"

labels = {
  team = "ithuriel"
}
