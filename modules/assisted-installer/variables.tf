variable "cluster_name" {
  description = "Name of the OpenShift cluster"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version to install"
  type        = string
}

variable "base_dns_domain" {
  description = "Base DNS domain for the cluster"
  type        = string
}

variable "cluster_network_cidr" {
  description = "CIDR for cluster network"
  type        = string
}

variable "service_network_cidr" {
  description = "CIDR for service network"
  type        = string
}

variable "host_network_cidr" {
  description = "CIDR for host network"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for cluster access"
  type        = string
}

variable "pull_secret" {
  description = "OpenShift pull secret"
  type        = string
  sensitive   = true
}

variable "assisted_service_url" {
  description = "URL of the Assisted Installer service"
  type        = string
}

variable "hosts" {
  description = "List of hosts to be added to the cluster"
  type = list(object({
    hostname = string
    role     = string
    mac_address = string
  }))
}

variable "proxy_settings" {
  description = "Proxy configuration for the cluster"
  type = object({
    http_proxy  = optional(string)
    https_proxy = optional(string)
    no_proxy    = optional(string)
  })
  default = {
    http_proxy  = null
    https_proxy = null
    no_proxy    = null
  }
}

variable "custom_manifests" {
  description = "List of custom manifests to apply to the cluster"
  type = list(object({
    filename = string
    content  = string
  }))
  default = []
}

variable "additional_ntp_sources" {
  description = "Additional NTP sources for cluster nodes"
  type        = list(string)
  default     = []
}
