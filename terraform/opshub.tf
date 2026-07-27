# OpsHub Proxmox API access (dashboard plugin).
# Creates opshub@pve!opshub with audit + power + guest-agent file privileges.
# Wire the token into opshub/.env.local or Settings → Proxmox after apply.

resource "proxmox_virtual_environment_role" "opshub" {
  count = var.manage_opshub_api ? 1 : 0

  role_id = var.opshub_api_role_id

  privileges = [
    "Datastore.Audit",
    "Mapping.Audit",
    "Pool.Audit",
    "SDN.Audit",
    "Sys.Audit",
    "VM.Audit",
    "VM.Console",
    "VM.GuestAgent.Audit",
    "VM.GuestAgent.FileRead",
    "VM.GuestAgent.FileWrite",
    "VM.PowerMgmt",
  ]
}

resource "proxmox_virtual_environment_user" "opshub" {
  count = var.manage_opshub_api ? 1 : 0

  user_id = var.opshub_api_user_id
  comment = "OpsHub dashboard API (managed by Terraform)"
  enabled = true
}

resource "proxmox_user_token" "opshub" {
  count = var.manage_opshub_api ? 1 : 0

  user_id               = proxmox_virtual_environment_user.opshub[0].user_id
  token_name            = var.opshub_api_token_name
  comment               = "OpsHub Phase 3+ guest status and power actions"
  privileges_separation = false
}

resource "proxmox_acl" "opshub" {
  count = var.manage_opshub_api ? 1 : 0

  path      = "/"
  propagate = true
  role_id   = proxmox_virtual_environment_role.opshub[0].role_id
  user_id   = proxmox_virtual_environment_user.opshub[0].user_id
}
