output "zfs_pools" {
  description = "ZFS pools managed by Terraform"
  value       = { for name, pool in proxmox_node_disk_zfs.pool : name => pool.devices }
}

output "vms" {
  description = "Standalone VMs: name -> VMID"
  value       = { for name, vm in module.vm : name => vm.vm_id }
}

output "containers" {
  description = "LXC containers: name -> VMID"
  value       = { for name, ct in proxmox_virtual_environment_container.ct : name => ct.vm_id }
}

output "backup_storage_id" {
  description = "Active vzdump target datastore (change for slot-3 or PBS migration)"
  value       = var.backup_storage_enabled ? var.backup_storage_id : null
}

output "backup_jobs" {
  description = "Backup job ids managed by Terraform"
  value       = var.backup_storage_enabled ? keys(var.backup_jobs) : []
}

output "opshub_proxmox_token_id" {
  description = "OpsHub API token id (user@realm!token) for PROXMOX_TOKEN_ID / Settings → Proxmox"
  value       = var.manage_opshub_api ? proxmox_user_token.opshub[0].id : null
}

output "opshub_proxmox_token_secret" {
  description = "OpsHub API token secret — only available on create; paste into OpsHub immediately"
  value       = var.manage_opshub_api ? proxmox_user_token.opshub[0].value : null
  sensitive   = true
}
