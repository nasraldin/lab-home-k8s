provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # Fresh Proxmox install uses a self-signed certificate.
  insecure = true

  # Used only for uploading cloud-init snippets (VMs / k8s clusters).
  # Requires your SSH key on the node: ssh-copy-id root@<node-ip>
  ssh {
    agent    = true
    username = "root"
  }
}
