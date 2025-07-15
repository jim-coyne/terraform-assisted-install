# Terraform Assisted Install - Red Hat OpenShift Cluster Deployment

This Terraform configuration provides an Infrastructure-as-Code approach to deploying OpenShift clusters using the **Red Hat Assisted Installer API** 

## Prerequisites

- Terraform >= 1.0
- OCM CLI installed and configured
- Access to Red Hat OpenShift Assisted Installer service
- OpenShift pull secret (from console.redhat.com/openshift/install/pull-secret)
- `curl` and `jq` command-line tools

## Authentication Setup

This configuration uses OCM (OpenShift Cluster Manager) CLI for authentication.

### Install OCM CLI

**macOS (with Homebrew):**
```bash
brew install ocm
```

**Linux/Other:**
Download from https://github.com/openshift-online/ocm-cli/releases

### Login to OCM
```bash
./ocm-browser-auth.sh
```
**Verify authentication:**
```bash
ocm whoami
```
### Deployment
```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Deploy the cluster
terraform apply
```

### Get Discovery ISO
After deployment, get the discovery ISO URL:
```bash
# Option 1: Use terraform output
terraform output discovery_iso_url


### Download and Boot ISO
```bash
# Download the discovery ISO
curl -L "$(terraform output -raw discovery_iso_url)" -o discovery.iso

# Boot your target hosts from this ISO
# Hosts will automatically register with the cluster
```

### Monitor Installation
```bash
# Monitor cluster progress
./monitor-cluster.sh

# Check cluster status
terraform output cluster_status
```

## 📁 Project Structure
```
├── main.tf                 # Main terraform configuration
├── variables.tf            # Variable definitions
├── terraform.tfvars       # Your configuration values
├── modules/
│   └── assisted-installer/ # Assisted installer module
├── scripts/
│   ├── monitor-cluster.sh      # Monitor cluster status
│   └── setup-credentials.sh   # Setup script
└── tmp/                   # Temporary files (auto-generated)
    ├── cluster_response.json
    ├── infra_env_response.json
    └── iso_download.json
```

## Configuration

### Required Variables
- **`cluster_name`**: Name of your OpenShift cluster
- **`base_dns_domain`**: DNS domain for cluster endpoints  
- **`ssh_public_key`**: SSH key for cluster access
- **`pull_secret`**: OpenShift pull secret (JSON format)
- **`hosts`**: List of hosts (minimum 3 masters for HA)

### Optional Variables
- **`proxy_settings`**: HTTP/HTTPS proxy configuration
- **`custom_manifests`**: Custom Kubernetes manifests
- **`additional_ntp_sources`**: Additional NTP time sources
- **`openshift_version`**: OpenShift version (default: 4.15)

### Host Configuration
Each host requires:
```hcl
{
  hostname    = "master-01"
  role        = "master"     # or "worker"
  mac_address = "aa:bb:cc:dd:ee:01"
}
```

**Important**: OpenShift requires exactly 3 master nodes for HA clusters.

## Advanced Usage

### Proxy Configuration
```hcl
proxy_settings = {
  http_proxy  = "http://proxy.example.com:8080"
  https_proxy = "https://proxy.example.com:8080"
  no_proxy    = "127.0.0.1,localhost,.local"
}
```

### Custom Manifests
```hcl
custom_manifests = [
  {
    filename = "my-config.yaml"
    content  = "apiVersion: v1\nkind: ConfigMap\n..."
  }
]
```

## Monitoring & Troubleshooting
### Check Status
```bash

# Check current status
terraform output cluster_status

# View all outputs
terraform output
```

### Common Commands
```bash
# Get discovery ISO URL
terraform output discovery_iso_url

# Get cluster ID  
terraform output cluster_id

# Get infra-env ID
terraform output infra_env_id
```

### Log Files
- `tmp/validation.log` - Configuration validation
- `tmp/cluster_response.json` - Cluster creation response
- `tmp/infra_env_response.json` - Infrastructure environment details
- `tmp/iso_download.json` - ISO download information

##  Cleanup

```bash
# Destroy the cluster and all resources
terraform destroy

# Clean up temporary files
make clean
```

## API Integration

This implementation uses the Red Hat Assisted Installer API:

- **Cluster Creation**: `POST /api/assisted-install/v2/clusters`
- **Infrastructure Environment**: `POST /api/assisted-install/v2/infra-envs`
- **ISO Generation**: `GET /api/assisted-install/v2/infra-envs/{id}/downloads/image-url`
- **Status Monitoring**: `GET /api/assisted-install/v2/clusters/{id}`

## Additional Resources

- [OpenShift Assisted Installer Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_on_prem_assisted/index.html)
- [OCM CLI Documentation](https://github.com/openshift-online/ocm-cli)
- [Red Hat Console](https://console.redhat.com/)
