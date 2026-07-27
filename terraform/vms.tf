module "vm" {
  source   = "./modules/vm"
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  pool_id   = each.value.pool
  tags      = each.value.tags

  cores        = each.value.cores
  cpu_limit    = each.value.cpu_limit
  memory       = each.value.memory
  disk_gb      = each.value.disk_gb
  data_disk_gb = try(each.value.data_disk_gb, null)
  datastore_id = var.vm_datastore

  bridge      = coalesce(each.value.bridge, var.network_bridge)
  mac_address = each.value.mac_address
  vlan_id     = each.value.vlan_id
  ip_address  = each.value.ip
  gateway     = each.value.ip == "dhcp" ? null : var.network_gateway

  image_file_id       = proxmox_download_file.cloud_image[each.value.image].id
  image_name          = each.value.image
  username            = var.default_username
  ssh_keys            = [trimspace(var.ssh_public_key)]
  vendor_data_file_id = proxmox_virtual_environment_file.vendor_data[0].id

  startup_order      = each.value.startup_order
  startup_up_delay   = each.value.startup_up_delay
  startup_down_delay = each.value.startup_down_delay

  depends_on = [
    proxmox_virtual_environment_pool.pool,
    proxmox_node_disk_zfs.pool,
  ]
}
