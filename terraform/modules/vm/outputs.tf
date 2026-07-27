output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "effective_config" {
  description = "Effective image and network inputs applied to this VM"
  value = {
    image_name = var.image_name
    bridge     = proxmox_virtual_environment_vm.this.network_device[0].bridge
    vlan_id    = proxmox_virtual_environment_vm.this.network_device[0].vlan_id
    ip_address = proxmox_virtual_environment_vm.this.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "ipv4_addresses" {
  description = "Addresses reported by the QEMU guest agent"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}
