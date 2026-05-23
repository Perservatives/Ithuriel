project_id              = "ithuriel-prod"
region                  = "us-central1"
environment             = "prod"
api_image               = "us-central1-docker.pkg.dev/ithuriel-prod/ithuriel/api:latest"
dashboard_image         = "us-central1-docker.pkg.dev/ithuriel-prod/ithuriel/dashboard:latest"
processor_source_bucket = "ithuriel-prod-terraform-state"
processor_source_object = "processor/prod.zip"
firebase_project_id     = "ithuriel-prod"

labels = {
  team = "ithuriel"
}
