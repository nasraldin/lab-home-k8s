resource "proxmox_virtual_environment_pool" "pool" {
  for_each = var.pools

  pool_id = each.key
  comment = each.value
}
