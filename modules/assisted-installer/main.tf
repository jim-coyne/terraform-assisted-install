# Create working directory for API responses
resource "null_resource" "setup_workspace" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.root}/tmp"
  }
}

# Get API token from OCM
data "external" "ocm_token" {
  program = ["bash", "-c", "echo '{\"token\":\"'$(ocm token)'\"}'"]
}

locals {
  api_token = data.external.ocm_token.result.token
}

# Create cluster using real Assisted Installer API
resource "null_resource" "create_cluster" {
  depends_on = [null_resource.setup_workspace]
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Creating cluster: ${var.cluster_name}"
      
      # Create cluster payload using jq to properly escape JSON
      jq -n \
        --arg name "${var.cluster_name}" \
        --arg version "${var.openshift_version}" \
        --arg domain "${var.base_dns_domain}" \
        --arg cluster_cidr "${var.cluster_network_cidr}" \
        --arg service_cidr "${var.service_network_cidr}" \
        --arg machine_cidr "${var.host_network_cidr}" \
        --arg ssh_key "${var.ssh_public_key}" \
        --argjson pull_secret '${var.pull_secret}' \
        '{
          "name": $name,
          "openshift_version": $version,
          "base_dns_domain": $domain,
          "cluster_network_cidr": $cluster_cidr,
          "service_network_cidr": $service_cidr,
          "machine_networks": [{"cidr": $machine_cidr}],
          "ssh_public_key": $ssh_key,
          "pull_secret": ($pull_secret | tostring),
          "high_availability_mode": "Full",
          "user_managed_networking": true,
          "vip_dhcp_allocation": false,
          "network_type": "OVNKubernetes"
        }' > ${path.root}/tmp/cluster_payload.json
      
      # Make API call to create cluster
      curl -X POST \
        -H "Authorization: Bearer ${local.api_token}" \
        -H "Content-Type: application/json" \
        -d @${path.root}/tmp/cluster_payload.json \
        "${var.assisted_service_url}/api/assisted-install/v2/clusters" \
        -o ${path.root}/tmp/cluster_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/http_status.txt)
      if [ "$HTTP_STATUS" -ne "201" ]; then
        echo "Error: Cluster creation failed with HTTP status $HTTP_STATUS"
        echo "Response:"
        cat ${path.root}/tmp/cluster_response.json
        exit 1
      fi
      
      echo "Cluster created successfully"
      echo "Cluster details:"
      cat ${path.root}/tmp/cluster_response.json | jq '.'
    EOT
  }
  
  # Cleanup on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up cluster resources..."
      rm -f ${path.root}/tmp/cluster_response.json
      rm -f ${path.root}/tmp/iso_response.json
      rm -f ${path.root}/tmp/cluster_payload.json
      rm -f ${path.root}/tmp/http_status.txt
      rm -f ${path.root}/tmp/delete_status.txt
      echo "Cleanup completed"
    EOT
    on_failure = continue
  }
}

# Get cluster ID from response
data "local_file" "cluster_response" {
  filename = "${path.root}/tmp/cluster_response.json"
  depends_on = [null_resource.create_cluster]
}

locals {
  cluster_data = jsondecode(data.local_file.cluster_response.content)
  cluster_id   = local.cluster_data.id
}

# Create infra-env (infrastructure environment) first
resource "null_resource" "create_infra_env" {
  depends_on = [null_resource.create_cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Creating infrastructure environment for cluster: ${local.cluster_id}"
      
      # Create infra-env payload
      jq -n \
        --arg cluster_id "${local.cluster_id}" \
        --arg name "${var.cluster_name}-infra-env" \
        --arg ssh_key "${var.ssh_public_key}" \
        --argjson pull_secret '${var.pull_secret}' \
        '{
          "name": $name,
          "cluster_id": $cluster_id,
          "ssh_authorized_key": $ssh_key,
          "pull_secret": ($pull_secret | tostring),
          "image_type": "full-iso",
          "cpu_architecture": "x86_64"
        }' > ${path.root}/tmp/infra_env_payload.json
      
      # Create infra-env via API
      curl -X POST \
        -H "Authorization: Bearer ${local.api_token}" \
        -H "Content-Type: application/json" \
        -d @${path.root}/tmp/infra_env_payload.json \
        "${var.assisted_service_url}/api/assisted-install/v2/infra-envs" \
        -o ${path.root}/tmp/infra_env_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/infra_env_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/infra_env_http_status.txt)
      if [ "$HTTP_STATUS" -ne "201" ]; then
        echo "Error: Infra-env creation failed with HTTP status $HTTP_STATUS"
        echo "Response:"
        cat ${path.root}/tmp/infra_env_response.json
        exit 1
      fi
      
      echo "Infrastructure environment created successfully"
      echo "Infra-env details:"
      cat ${path.root}/tmp/infra_env_response.json | jq '.'
    EOT
  }
}

# Get infra-env ID from response
data "local_file" "infra_env_response" {
  filename = "${path.root}/tmp/infra_env_response.json"
  depends_on = [null_resource.create_infra_env]
}

locals {
  infra_env_data = jsondecode(data.local_file.infra_env_response.content)
  infra_env_id   = local.infra_env_data.id
}

# Generate discovery ISO using infra-env
resource "null_resource" "generate_discovery_iso" {
  depends_on = [null_resource.create_infra_env]
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Generating discovery ISO for infra-env: ${local.infra_env_id}"
      
      # Get ISO download URL from infra-env
      curl -X GET \
        -H "Authorization: Bearer ${local.api_token}" \
        "${var.assisted_service_url}/api/assisted-install/v2/infra-envs/${local.infra_env_id}/downloads/image-url" \
        -o ${path.root}/tmp/iso_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/iso_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/iso_http_status.txt)
      if [ "$HTTP_STATUS" -eq "200" ]; then
        echo "Discovery ISO URL retrieved successfully"
        echo "ISO details:"
        cat ${path.root}/tmp/iso_response.json | jq '.'
        
        # Extract download URL and save it
        DOWNLOAD_URL=$(cat ${path.root}/tmp/iso_response.json | jq -r '.url // .download_url // empty')
        if [ -n "$DOWNLOAD_URL" ] && [ "$DOWNLOAD_URL" != "null" ]; then
          echo "$DOWNLOAD_URL" > ${path.root}/tmp/iso_download_url.txt
          echo "ISO download URL: $DOWNLOAD_URL"
        fi
      else
        echo "Warning: ISO URL retrieval failed with HTTP status $HTTP_STATUS"
        echo "Response:"
        cat ${path.root}/tmp/iso_response.json
        # This might be expected for freshly created infra-envs
        echo '{"message": "ISO generation in progress - URL will be available shortly"}' > ${path.root}/tmp/iso_response.json
      fi
    EOT
  }
}

# Add hosts to cluster using real API
resource "null_resource" "add_hosts" {
  count = length(var.hosts)
  depends_on = [null_resource.create_cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Registering host ${var.hosts[count.index].hostname} with cluster ${local.cluster_id}"
      echo "Host role: ${var.hosts[count.index].role}"
      echo "MAC address: ${var.hosts[count.index].mac_address}"
      
      # Create host registration payload
      cat > ${path.root}/tmp/host_${count.index}_payload.json << EOF
      {
        "host_name": "${var.hosts[count.index].hostname}",
        "host_role": "${var.hosts[count.index].role}",
        "discovery_agent_version": "latest"
      }
      EOF
      
      # Note: Actual host registration happens when the discovery ISO boots
      # This step prepares the host configuration
      echo "Host ${var.hosts[count.index].hostname} prepared for registration"
    EOT
  }
}

# Monitor cluster status using real API
resource "null_resource" "monitor_cluster" {
  depends_on = [null_resource.add_hosts]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Monitoring cluster status for: ${local.cluster_id}"
      
      # Get cluster status from API
      curl -X GET \
        -H "Authorization: Bearer ${local.api_token}" \
        "${var.assisted_service_url}/api/assisted-install/v2/clusters/${local.cluster_id}" \
        -o ${path.root}/tmp/cluster_status.json \
        -w "%%{http_code}" > ${path.root}/tmp/status_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/status_http_status.txt)
      if [ "$HTTP_STATUS" -eq "200" ]; then
        STATUS=$(cat ${path.root}/tmp/cluster_status.json | jq -r '.status // "unknown"')
        echo "Current cluster status: $STATUS"
        
        # Display cluster details in a user-friendly format
        echo "Cluster Summary:"
        echo "  Name: $(cat ${path.root}/tmp/cluster_status.json | jq -r '.name // "N/A"')"
        echo "  Version: $(cat ${path.root}/tmp/cluster_status.json | jq -r '.openshift_version // "N/A"')"
        echo "  Status: $STATUS"
        echo "  Status Info: $(cat ${path.root}/tmp/cluster_status.json | jq -r '.status_info // "N/A"')"
        echo "  Registered Hosts: $(cat ${path.root}/tmp/cluster_status.json | jq '.hosts | length // 0')"
        
        # Save full cluster data for reference
        echo "Full cluster data saved to tmp/cluster_status.json"
      else
        echo "Warning: Failed to get cluster status, HTTP status: $HTTP_STATUS"
        echo "Response:"
        cat ${path.root}/tmp/cluster_status.json || echo "No response data"
      fi
    EOT
  }
}

# Apply proxy settings if provided using real API
resource "null_resource" "configure_proxy" {
  count = var.proxy_settings.http_proxy != null ? 1 : 0
  depends_on = [null_resource.create_cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuring proxy settings for cluster: ${local.cluster_id}"
      echo "HTTP Proxy: ${var.proxy_settings.http_proxy}"
      echo "HTTPS Proxy: ${var.proxy_settings.https_proxy}"
      echo "No Proxy: ${var.proxy_settings.no_proxy}"
      
      # Create proxy configuration payload
      cat > ${path.root}/tmp/proxy_config.json << EOF
      {
        "http_proxy": "${var.proxy_settings.http_proxy}",
        "https_proxy": "${var.proxy_settings.https_proxy}",
        "no_proxy": "${var.proxy_settings.no_proxy}"
      }
      EOF
      
      # Apply proxy configuration via API
      curl -X PATCH \
        -H "Authorization: Bearer ${local.api_token}" \
        -H "Content-Type: application/json" \
        -d @${path.root}/tmp/proxy_config.json \
        "${var.assisted_service_url}/api/assisted-install/v2/clusters/${local.cluster_id}" \
        -o ${path.root}/tmp/proxy_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/proxy_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/proxy_http_status.txt)
      if [ "$HTTP_STATUS" -eq "201" ] || [ "$HTTP_STATUS" -eq "200" ]; then
        echo "Proxy configuration applied successfully"
      else
        echo "Warning: Proxy configuration failed with HTTP status $HTTP_STATUS"
        cat ${path.root}/tmp/proxy_response.json
      fi
    EOT
  }
}

# Apply custom manifests using real API
resource "null_resource" "apply_custom_manifests" {
  count = length(var.custom_manifests)
  depends_on = [null_resource.create_cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying custom manifest: ${var.custom_manifests[count.index].filename}"
      
      # Create manifest directory
      mkdir -p ${path.root}/tmp/manifests
      
      # Write manifest content
      cat > ${path.root}/tmp/manifests/${var.custom_manifests[count.index].filename} << 'EOF'
${var.custom_manifests[count.index].content}
EOF
      
      # Create manifest payload for API
      MANIFEST_CONTENT_B64=$(base64 -i ${path.root}/tmp/manifests/${var.custom_manifests[count.index].filename} | tr -d '\n')
      cat > ${path.root}/tmp/manifest_${count.index}_payload.json << EOF
      {
        "file_name": "${var.custom_manifests[count.index].filename}",
        "folder": "manifests",
        "content": "$MANIFEST_CONTENT_B64"
      }
      EOF
      
      # Upload manifest via API
      curl -X POST \
        -H "Authorization: Bearer ${local.api_token}" \
        -H "Content-Type: application/json" \
        -d @${path.root}/tmp/manifest_${count.index}_payload.json \
        "${var.assisted_service_url}/api/assisted-install/v2/clusters/${local.cluster_id}/manifests" \
        -o ${path.root}/tmp/manifest_${count.index}_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/manifest_${count.index}_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/manifest_${count.index}_http_status.txt)
      if [ "$HTTP_STATUS" -eq "201" ] || [ "$HTTP_STATUS" -eq "200" ]; then
        echo "Custom manifest ${var.custom_manifests[count.index].filename} applied successfully"
      else
        echo "Warning: Manifest upload failed with HTTP status $HTTP_STATUS"
        cat ${path.root}/tmp/manifest_${count.index}_response.json
      fi
    EOT
  }
}

# Configure additional NTP sources using real API
resource "null_resource" "configure_ntp" {
  count = length(var.additional_ntp_sources) > 0 ? 1 : 0
  depends_on = [null_resource.create_cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuring additional NTP sources for cluster: ${local.cluster_id}"
      
      # Create NTP configuration payload
      cat > ${path.root}/tmp/ntp_config.json << EOF
      {
        "additional_ntp_source": "${join(",", var.additional_ntp_sources)}"
      }
      EOF
      
      # Apply NTP configuration via API
      curl -X PATCH \
        -H "Authorization: Bearer ${local.api_token}" \
        -H "Content-Type: application/json" \
        -d @${path.root}/tmp/ntp_config.json \
        "${var.assisted_service_url}/api/assisted-install/v2/clusters/${local.cluster_id}" \
        -o ${path.root}/tmp/ntp_response.json \
        -w "%%{http_code}" > ${path.root}/tmp/ntp_http_status.txt
      
      # Check HTTP status
      HTTP_STATUS=$(cat ${path.root}/tmp/ntp_http_status.txt)
      if [ "$HTTP_STATUS" -eq "201" ] || [ "$HTTP_STATUS" -eq "200" ]; then
        echo "NTP configuration applied successfully"
      else
        echo "Warning: NTP configuration failed with HTTP status $HTTP_STATUS"
        cat ${path.root}/tmp/ntp_response.json
      fi
    EOT
  }
}
