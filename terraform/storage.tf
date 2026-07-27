resource "proxmox_node_disk_zfs" "pool" {
  for_each = var.zfs_pools

  node_name = var.node_name
  name      = each.key
  devices   = [each.value.device]
  raidlevel = each.value.raidlevel

  ashift      = each.value.ashift
  compression = each.value.compression

  add_storage = each.value.add_storage

  # On `terraform destroy`: remove the datastore entry but never wipe the disk.
  cleanup_config = true
  cleanup_disks  = false
}
