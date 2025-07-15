# Terraform Assisted Install

This Terraform configuration provides an Infrastructure-as-Code approach to deploying OpenShift clusters using the Assisted Installer service with enterprise features and custom operator support.

## Features

- **Automated cluster creation and configuration**
- **Host management and registration** (supports 3 control plane + 3 worker nodes)
- **Discovery ISO generation**
- **Installation monitoring**
- **Modular design for reusability**
- **Enterprise proxy support** (HTTP/HTTPS proxy with no-proxy bypass)
- **Custom manifest deployment** (Cilium, ACI Operator, GPU Operator)
- **Additional NTP sources configuration**
- **Network policy management**
- **GPU worker node support with custom kernel parameters**

## Prerequisites

- Terraform >= 1.0
- Access to OpenShift Assisted Installer service
- Valid API token
- OpenShift pull secret

## Usage

1. Copy the example configuration:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration

### Required Variables

- `cluster_name`: Name of your OpenShift cluster
- `base_dns_domain`: DNS domain for cluster endpoints
- `ssh_public_key`: SSH key for cluster access
- `pull_secret`: OpenShift pull secret
- `api_token`: Assisted Installer API token
- `hosts`: List of hosts to add to the cluster (each with hostname, role, mac_address)

### Optional Enterprise Features

- `proxy_settings`: HTTP/HTTPS proxy configuration with no-proxy bypass rules
- `additional_ntp_sources`: Additional NTP servers for time synchronization
- `custom_manifests`: List of custom Kubernetes manifests to deploy

### Sample Custom Manifests Included

The configuration includes examples for:
- **Cilium Operator**: Advanced networking with eBPF
- **ACI Operator**: Cisco ACI integration for enterprise networking
- **GPU Operator**: NVIDIA GPU support for AI/ML workloads
- **Network Policies**: Security policies for namespace isolation
- **MachineConfig**: Custom kernel parameters for GPU nodes

## Outputs

- `cluster_id`: Unique identifier for the created cluster
- `discovery_iso_url`: Download URL for the discovery ISO
- `cluster_status`: Current installation status

## Module Structure

- `modules/assisted-installer/`: Core functionality
  - Cluster creation and management
  - Host registration and configuration
  - Proxy and NTP configuration
  - Custom manifest deployment
  - Installation orchestration and monitoring

## Enterprise Features

### Proxy Support
Configure enterprise proxy settings for cluster communications:
```hcl
proxy_settings = {
  http_proxy  = "http://proxy.example.com:8080"
  https_proxy = "http://proxy.example.com:8080"
  no_proxy    = "localhost,127.0.0.1,.example.com"
}
```

### Custom Operators
Deploy enterprise operators automatically:
- Cilium for advanced networking
- ACI Operator for Cisco integration
- GPU Operator for AI/ML workloads

### Resource Count
Total resources created: **18**
- 1 validation resource
- 6 host resources (3 masters + 3 workers)
- 5 custom manifest resources
- 1 proxy configuration
- 1 NTP configuration
- 4 base cluster resources

## Files Generated

The configuration creates several output files in `tmp/`:
- `cluster_response.json`: Cluster metadata
- `proxy_config.json`: Proxy configuration
- `ntp_config.json`: NTP configuration
- `iso_response.json`: Discovery ISO information
- `manifests/`: Directory with all custom operator manifests

## Contributing

This project provides a modern Terraform-based approach to OpenShift cluster deployment, replacing traditional Python-based tools with Infrastructure-as-Code best practices. Perfect for FlexPod and enterprise environments requiring advanced networking, GPU support, and proxy configurations.
