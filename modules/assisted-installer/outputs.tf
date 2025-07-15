output "cluster_id" {
  description = "ID of the created cluster"
  value       = local.cluster_id
}

output "infra_env_id" {
  description = "ID of the created infrastructure environment"
  value       = try(local.infra_env_id, "Not created yet")
}

output "discovery_iso_url" {
  description = "URL to download the discovery ISO"
  value       = fileexists("${path.root}/tmp/iso_download_url.txt") ? trim(file("${path.root}/tmp/iso_download_url.txt"), "\n") : (fileexists("${path.root}/tmp/iso_download.json") ? try(jsondecode(file("${path.root}/tmp/iso_download.json"))["url"], "ISO URL not found") : (fileexists("${path.root}/tmp/iso_response.json") ? try(jsondecode(file("${path.root}/tmp/iso_response.json"))["url"], try(jsondecode(file("${path.root}/tmp/iso_response.json"))["download_url"], "ISO generation in progress - check tmp/iso_response.json")) : "ISO not yet generated - run terraform apply"))
}

output "cluster_status" {
  description = "Current status of the cluster"
  value       = fileexists("${path.root}/tmp/cluster_status.json") ? try(jsondecode(file("${path.root}/tmp/cluster_status.json"))["status"], "unknown") : "unknown"
}

output "cluster_data" {
  description = "Full cluster data"
  value       = local.cluster_data
  sensitive   = true
}

output "cluster_console_url" {
  description = "URL to access the OpenShift console"
  value       = fileexists("${path.root}/tmp/cluster_status.json") ? try(jsondecode(file("${path.root}/tmp/cluster_status.json"))["api_vip"], "Not available yet") : "Not available yet"
}
