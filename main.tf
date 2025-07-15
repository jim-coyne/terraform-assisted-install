terraform {
  required_version = ">= 1.0"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Simple validation for required variables
resource "null_resource" "validate_config" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Validating required configuration..."
      
      # Create tmp directory if it doesn't exist
      mkdir -p ${path.root}/tmp
      
      if [ -z "${var.cluster_name}" ]; then
        echo "Error: cluster_name is required"
        exit 1
      fi
      
      if [ -z "${var.base_dns_domain}" ]; then
        echo "Error: base_dns_domain is required"
        exit 1
      fi
      
      if [ -z "${var.api_token}" ]; then
        echo "Error: api_token is required"
        exit 1
      fi
      
      if [ -z "${var.pull_secret}" ]; then
        echo "Error: pull_secret is required"
        exit 1
      fi
      
      if [ -z "${var.ssh_public_key}" ]; then
        echo "Error: ssh_public_key is required"
        exit 1
      fi
      
      echo "Configuration validation completed successfully"
      echo "timestamp: $(date)" > ${path.root}/tmp/validation.log
    EOT
  }
}

module "assisted_installer" {
  source     = "./modules/assisted-installer"
  depends_on = [null_resource.validate_config]

  cluster_name         = var.cluster_name
  openshift_version    = var.openshift_version
  base_dns_domain      = var.base_dns_domain
  cluster_network_cidr = var.cluster_network_cidr
  service_network_cidr = var.service_network_cidr
  host_network_cidr    = var.host_network_cidr
  ssh_public_key       = var.ssh_public_key
  pull_secret          = var.pull_secret
  assisted_service_url = var.assisted_service_url
  api_token            = var.api_token

  hosts                   = var.hosts
  proxy_settings          = var.proxy_settings
  custom_manifests        = var.custom_manifests
  additional_ntp_sources  = var.additional_ntp_sources
}

output "cluster_id" {
  value = module.assisted_installer.cluster_id
}

output "discovery_iso_url" {
  value = module.assisted_installer.discovery_iso_url
}

output "cluster_status" {
  value = module.assisted_installer.cluster_status
}
