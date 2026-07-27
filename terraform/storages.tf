# Additional directory datastores (ISO, templates, aux backup paths, etc.).
# Primary vzdump target for Stage 1 is still created in backup.tf (local-backup).

resource "proxmox_storage_directory" "extra" {
  for_each = var.directory_storages

  id    = each.key
  path  = each.value.path
  nodes = [var.node_name]

  content          = each.value.content
  create_base_path = each.value.create_base_path
  create_subdirs   = each.value.create_subdirs
  shared           = false
}
