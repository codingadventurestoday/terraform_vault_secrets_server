terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.49.0"
    }
  }
}

# Provider configuration.
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone = var.gcp_zone
}

# A simple network and firewall rule.
resource "google_compute_network" "default" {
  name = "vault-network"
}

resource "google_compute_firewall" "allow_vault_traffic" {
  name    = "allow-vault-traffic"
  network = google_compute_network.default.self_link
  allow {
    protocol = "tcp"
    ports    = ["8200"] # Default Vault port
  }
  // update the 
  source_ranges = ["69.113.0.25/32", "add_vm instance_ip"] 
}

resource "google_compute_instance" "vault_server" {
  name         = "vault-server-instance"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  # Network interface configuration.
  network_interface {
    network    = google_compute_network.default.self_link
    access_config {
      nat_ip = google_compute_address.static_ip.address 
    }
  }

  scheduling {
    automatic_restart = true
    provisioning_model = "SPOT"
    on_host_maintenance = "TERMINATE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "Starting Vault server setup..."

    sudo apt-get update
    sudo apt-get install -y wget unzip

    # Install Vault
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y vault

    # Create a non-privileged user to run Vault
    sudo useradd --system --home /etc/vault_user.d --shell /bin/bash vault_user

    # Set up the Vault configuration directory and file
    sudo mkdir --parents /etc/vault_user.d/
    sudo touch /etc/vault_user.d/vault.hcl
    sudo chown --recursive vault_user:vault_user /etc/vault_user.d/
    sudo chmod 640 /etc/vault_user.d/vault.hcl

    # Write the Vault server configuration to the file.
    # This uses a simple file backend. For production, consider using
    # a more robust backend like Cloud Storage.
    sudo tee /etc/vault_user.d/vault.hcl > /dev/null <<EOF
    storage "file" {
      path = "/etc/vault_user.d/data"
    }
 
    listener "tcp" {
      //Change to IP address of client vm instance 
      address     = "0.0.0.0:8200"
      // WARNING: tls_disable is for development only!
      tls_disable = true 
    }

    listener "tcp" {
      //Change to IP address of client vm instance 
      address     = "68.129.131.117:8200"
      // WARNING: tls_disable is for development only!
      tls_disable = true 
    }

    ui = true
    EOF

    # Configure the systemd service to ensure automatic restarts
    sudo tee /etc/systemd/system/vault.service > /dev/null <<EOF
    [Unit]
    Description="HashiCorp Vault - A tool for managing secrets"
    Documentation=https://www.vaultproject.io/docs/
    Requires=network-online.target
    After=network-online.target

    [Service]
    User=vault_user
    Group=vault_user
    ProtectSystem=full
    ProtectHome=read-only
    AmbientCapabilities=CAP_IPC_LOCK
    ExecStart=/usr/bin/vault server -config=/etc/vault_user.d/vault.hcl
    ExecReload=/bin/kill --signal HUP $MAINPID
    KillMode=process
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target
    EOF

    # Start and enable the Vault service
    sudo systemctl daemon-reload
    sudo systemctl enable vault
    sudo systemctl start vault
    echo "Vault server setup complete. The server is now running."
  EOT
}

# Output the public IP address of the Vault server.
output "vault_server_public_ip" {
  value = google_compute_instance.vault_server.network_interface.0.access_config.0.nat_ip
}

resource "google_compute_address" "static_ip" {
  name = "vault-static-ip"
}

resource "google_monitoring_alert_policy" "vm_shutdown_alert" {
  display_name = "VM Instance Shutdown Alert"
  combiner     = "OR"
  project      = var.gcp_project_id

  conditions {
    display_name = "VM is terminated"
    condition_matched_log {
      filter = <<EOT
      resource.type="gce_instance"
      jsonPayload.event.action="gcp.compute.v1.instance.terminate"
      EOT
    }
  }

  documentation {
    content   = "An alert has been triggered because a GCE VM instance was terminated."
    mime_type = "text/markdown"
  }

  notification_channels = [
    google_monitoring_notification_channel.email_channel.id,
  ]
}

resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "Email Notification Channel"
  type         = "email"
  labels = {
    email_address = "codingadventurestoday@gamil.com"
  }
}