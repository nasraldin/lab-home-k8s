# Backup datastore + scheduled vzdump jobs.
# Proxmox backup schedule — see dev-homelab maintenance guide.

locals {
  # Stage 1: backup.tf creates local-backup. Stage 2: aux-backup lives in directory_storages.
  backup_storage_in_extra = contains(keys(var.directory_storages), var.backup_storage_id)
}

resource "proxmox_storage_directory" "backup" {
  count = var.backup_storage_enabled && !local.backup_storage_in_extra ? 1 : 0

  id    = var.backup_storage_id
  path  = var.backup_storage_path
  nodes = [var.node_name]

  content          = ["backup"]
  create_base_path = true
  create_subdirs   = true
  shared           = false
}

resource "proxmox_backup_job" "jobs" {
  for_each = var.backup_storage_enabled ? var.backup_jobs : {}

  id       = each.key
  schedule = each.value.schedule
  storage  = var.backup_storage_id
  node     = var.node_name

  enabled  = each.value.enabled
  mode     = each.value.mode
  compress = each.value.compress
  all      = each.value.all

  prune_backups    = each.value.prune_backups
  mailnotification = each.value.mailnotification
  mailto           = length(var.backup_notify_emails) > 0 ? var.backup_notify_emails : null

  depends_on = [
    proxmox_storage_directory.backup,
    proxmox_storage_directory.extra,
  ]
}
