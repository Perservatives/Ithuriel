// Vertex AI Vector Search — managed ANN index for Ithuriel context embeddings.
// 768-dim vectors (text-embedding-005). One index, one deployed endpoint.
// Streaming updates so the context processor can upsert as snapshots land.

resource "google_storage_bucket" "vector_index" {
  name                        = "${var.project_id}-ithuriel-vector-index"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.enabled]
}

// Seed object so the index can initialise from an (empty) location.
resource "google_storage_bucket_object" "vector_seed" {
  name    = "seed/empty.json"
  bucket  = google_storage_bucket.vector_index.name
  content = ""
}

resource "google_vertex_ai_index" "context" {
  provider     = google-beta
  region       = var.region
  display_name = "ithuriel-context"
  description  = "Semantic index over Ithuriel context snapshots (text-embedding-005, 768 dim)."

  metadata {
    contents_delta_uri = "gs://${google_storage_bucket.vector_index.name}/seed/"
    config {
      dimensions                  = 768
      approximate_neighbors_count = 50
      distance_measure_type       = "COSINE_DISTANCE"
      shard_size                  = "SHARD_SIZE_SMALL"

      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = 500
          leaf_nodes_to_search_percent = 7
        }
      }
    }
  }

  index_update_method = "STREAM_UPDATE"

  depends_on = [
    google_project_service.enabled,
    google_storage_bucket_object.vector_seed,
  ]
}

resource "google_vertex_ai_index_endpoint" "context" {
  provider     = google-beta
  region       = var.region
  display_name = "ithuriel-context-endpoint"
  description  = "Public endpoint serving the Ithuriel context vector index."

  public_endpoint_enabled = true

  depends_on = [google_project_service.enabled]
}

output "vector_search_index_id" {
  value       = google_vertex_ai_index.context.id
  description = "Vertex AI Vector Search index resource ID."
}

output "vector_search_endpoint_id" {
  value       = google_vertex_ai_index_endpoint.context.id
  description = "Vertex AI Vector Search endpoint resource ID."
}

output "vector_search_endpoint_host" {
  value       = google_vertex_ai_index_endpoint.context.public_endpoint_domain_name
  description = "Public host for ANN queries against the deployed index."
}
