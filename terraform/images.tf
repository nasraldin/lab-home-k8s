# Cloud images and LXC templates live on `local` (OS disk); guest disks go to data01.
# local content types (snippets/import) are owned by local-storage.tf.

resource "proxmox_download_file" "cloud_image" {
  for_each = var.cloud_images

  content_type = "import"
  datastore_id = proxmox_storage_directory.local.id
  node_name    = var.node_name
  url          = each.value.url
  file_name    = each.value.file_name
  overwrite    = false

  depends_on = [
    proxmox_storage_directory.local,
    terraform_data.local_snippets_ready,
  ]
}

resource "proxmox_download_file" "lxc_template" {
  for_each = var.lxc_templates

  content_type = "vztmpl"
  datastore_id = proxmox_storage_directory.local.id
  node_name    = var.node_name
  url          = each.value.url
  file_name    = each.value.file_name
  overwrite    = false

  depends_on = [
    proxmox_storage_directory.local,
    terraform_data.local_snippets_ready,
  ]
}

# Shared vendor-data: installs qemu-guest-agent in every plain VM so Proxmox
# and Terraform can see guest IPs. Only created once VMs exist.
resource "proxmox_virtual_environment_file" "vendor_data" {
  count = length(var.vms) > 0 ? 1 : 0

  content_type = "snippets"
  datastore_id = proxmox_storage_directory.local.id
  node_name    = var.node_name

  source_raw {
    file_name = "vendor-data-qemu-agent.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOF
  }

  depends_on = [
    proxmox_storage_directory.local,
    terraform_data.local_snippets_ready,
  ]
}
