variable "name" {
  description = "VM name (also used as cloud-init hostname)"
  type        = string
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  description = "Explicit VMID; null lets Proxmox pick the next free one"
  type        = number
  default     = null
}

variable "pool_id" {
  description = "Resource pool to place the VM in"
  type        = string
  default     = null
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "cores" {
  type    = number
  default = 2
}

variable "cpu_limit" {
  description = "Optional Proxmox cpulimit (fractional cores, e.g. 0.5). Null = unlimited."
  type        = number
  default     = null
}

variable "memory" {
  description = "Dedicated memory in MB"
  type        = number
  default     = 2048
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "data_disk_gb" {
  description = "Optional second disk (scsi1) for Longhorn; null = none"
  type        = number
  default     = null
}

variable "datastore_id" {
  description = "Datastore for the VM disk and cloud-init drive"
  type        = string
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  description = "Optional Proxmox VLAN tag for the VM network device"
  type        = number
  default     = null
}

variable "mac_address" {
  description = "Optional explicit MAC address for a stable IPv6 EUI-64 identity"
  type        = string
  default     = null

  validation {
    condition = (
      var.mac_address == null ||
      can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", var.mac_address))
    )
    error_message = "mac_address must be null or six colon-separated hexadecimal octets."
  }
}

variable "ip_address" {
  description = "Static address in CIDR form (192.168.68.20/22) or \"dhcp\""
  type        = string
  default     = "dhcp"
}

variable "gateway" {
  description = "IPv4 gateway; ignored when ip_address is dhcp"
  type        = string
  default     = null
}

variable "image_file_id" {
  description = "ID of an imported cloud image (e.g. local:import/debian-13-….qcow2)"
  type        = string
}

variable "image_name" {
  description = "Label for the cloud image (documentation / outputs)"
  type        = string
  default     = "debian-13"
}

variable "username" {
  description = "Default user created by cloud-init"
  type        = string
  default     = "nasr"
}

variable "ssh_keys" {
  description = "SSH public keys for the default user"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.ssh_keys) > 0
    error_message = "Provide at least one SSH public key (ssh_public_key in terraform.tfvars) or you will be locked out of the VM."
  }
}

variable "vendor_data_file_id" {
  description = "Optional cloud-init vendor-data snippet (e.g. qemu-guest-agent install)"
  type        = string
  default     = null
}

variable "started" {
  type    = bool
  default = true
}

variable "startup_order" {
  description = "Proxmox boot order (lower starts first). Null = no startup block."
  type        = number
  default     = null
}

variable "startup_up_delay" {
  description = "Seconds to wait after this VM starts before the next (Proxmox startup)."
  type        = number
  default     = null
}

variable "startup_down_delay" {
  description = "Seconds to wait after this VM stops before the next shutdown."
  type        = number
  default     = null
}
