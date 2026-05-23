variable "project_id" {
  description = "GCP project ID hosting Ithuriel."
  type        = string
}

variable "region" {
  description = "Primary region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "api_image" {
  description = "Full Artifact Registry URL of the Cloud Run API container image."
  type        = string
}

variable "gemini_api_key" {
  description = "Optional server-side Gemini key for paid tier proxying. Leave empty for BYOK only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_client_id" {
  description = "OAuth 2.0 client ID for Google sign-in (web client used by Cloud Run)."
  type        = string
}

variable "oauth_client_secret" {
  description = "OAuth 2.0 client secret."
  type        = string
  sensitive   = true
}

variable "allowed_origins" {
  description = "CORS-allowed origins for the API (web dashboard, localhost dev)."
  type        = list(string)
  default     = ["https://ithuriel.dev", "http://localhost:5173"]
}
