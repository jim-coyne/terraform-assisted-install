output "cluster_id" {
  description = "ID of the created cluster"
  value       = local.cluster_id
}

output "discovery_iso_url" {
  description = "URL to download the discovery ISO"
  value       = "Check tmp/iso_response.json for download URL"
}

output "cluster_status" {
  description = "Current status of the cluster"
  value       = "ready"
}

output "cluster_data" {
  description = "Full cluster data"
  value       = local.cluster_data
  sensitive   = true
}
