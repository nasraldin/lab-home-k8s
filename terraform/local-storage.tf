# Fresh Proxmox "local" (/var/lib/vz) ships without snippets (and sometimes
# without import). images.tf needs both for cloud images + vendor-data.
# Import the built-in datastore on first apply, then keep content types in sync.

import {
  to = proxmox_storage_directory.local
  id = "local"
}

locals {
  # https://pve01.lab.nasraldin.com:8006/ → pve01.lab.nasraldin.com
  pve_ssh_host = regex("https?://([^:/]+)", var.proxmox_endpoint)[0]
}

resource "proxmox_storage_directory" "local" {
  id   = "local"
  path = "/var/lib/vz"
  # Omit nodes — default local is cluster-wide; setting nodes trips a bpg provider
  # inconsistency (planned [pve01] vs actual []).

  content = [
    "backup",
    "iso",
    "vztmpl",
    "snippets",
    "import",
  ]

  create_base_path = true
  create_subdirs   = true
  shared           = false

  lifecycle {
    prevent_destroy = true
  }
}

# Provider update sets create-subdirs in storage.cfg but does not always create
# /var/lib/vz/snippets on an existing datastore. Force the side-effect via SSH
# so vendor-data uploads work on fresh installs without a manual pvesm step.
resource "terraform_data" "local_snippets_ready" {
  triggers_replace = [
    proxmox_storage_directory.local.id,
    join(",", sort(tolist(proxmox_storage_directory.local.content))),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      ssh -o BatchMode=yes -o ConnectTimeout=15 "root@${local.pve_ssh_host}" \
        'mkdir -p /var/lib/vz/snippets && pvesm set local --create-subdirs 1'
    EOT
  }

  depends_on = [proxmox_storage_directory.local]
}
