variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary GCP region"
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "api_image" {
  type        = string
  description = "Container image for the API Cloud Run service"
}

variable "dashboard_image" {
  type        = string
  description = "Container image for the Dashboard Cloud Run service"
  default     = ""
}

variable "processor_source_bucket" {
  type        = string
  description = "GCS bucket containing processor source zip"
}

variable "processor_source_object" {
  type        = string
  description = "Object name for processor source zip"
  default     = "processor.zip"
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project ID (usually same as project_id)"
  default     = ""
}

variable "labels" {
  type        = map(string)
  description = "Resource labels"
  default     = {}
}
