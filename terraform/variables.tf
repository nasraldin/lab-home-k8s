# --- Connection ---------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://192.168.68.13:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form user@realm!tokenid=secret (see README)"
  type        = string
  sensitive   = true
}

# --- OpsHub API access ----------------------------------------------------------

variable "manage_opshub_api" {
  description = "Create the OpsHub Proxmox user, role, ACL, and API token (opshub@pve!opshub)."
  type        = bool
  default     = true
}

variable "opshub_api_user_id" {
  description = "Proxmox user id for OpsHub (realm included)"
  type        = string
  default     = "opshub@pve"
}

variable "opshub_api_token_name" {
  description = "Token name; full id becomes user_id!token_name"
  type        = string
  default     = "opshub"
}

variable "opshub_api_role_id" {
  description = "Custom Proxmox role id granted to the OpsHub user"
  type        = string
  default     = "OpsHub"
}

variable "node_name" {
  description = "Proxmox node name as shown in the UI / `pvesh get /nodes`"
  type        = string
}

# --- Network / defaults ---------------------------------------------------------

variable "network_gateway" {
  description = "Default IPv4 gateway for static-IP guests"
  type        = string
  default     = "192.168.68.1"
}

variable "network_bridge" {
  description = "Default Proxmox bridge for guests"
  type        = string
  default     = "vmbr0"
}

variable "vm_datastore" {
  description = "Default datastore for guest disks"
  type        = string
  default     = "data01"
}

variable "default_username" {
  description = "Default admin user created in guests via cloud-init"
  type        = string
  default     = "nasr"
}

variable "ssh_public_key" {
  description = "Your SSH public key, injected into every guest. Required once you create VMs/CTs/clusters."
  type        = string
  default     = ""
}

# --- Node storage ----------------------------------------------------------------

variable "zfs_pools" {
  description = <<-EOT
    ZFS pools to create on node disks, keyed by pool name.
    Adding a new disk later = add one entry here, then `terraform apply`.
    Always use /dev/disk/by-id/ paths (stable, serial-based), never /dev/nvmeXn1.
  EOT
  type = map(object({
    device      = string
    raidlevel   = optional(string, "single")
    ashift      = optional(number, 12)
    compression = optional(string, "lz4")
    # false = ZFS pool only (no VM datastore). Use with directory_storages for backup/ISO.
    add_storage = optional(bool, true)
  }))
  default = {}
}

variable "directory_storages" {
  description = <<-EOT
    Extra Proxmox directory datastores (backup, ISO, templates, etc.).
    Used when a ZFS pool has add_storage = false, or for paths on rpool.
    Example after adding a 4 TB aux disk: aux-backup + aux-media on pool aux01.
  EOT
  type = map(object({
    path             = string
    content          = list(string)
    create_base_path = optional(bool, true)
    create_subdirs   = optional(bool, true)
  }))
  default = {}
}

# --- Grouping ---------------------------------------------------------------------

variable "pools" {
  description = "Proxmox resource pools (Datacenter -> Pools): pool id -> comment"
  type        = map(string)
  default     = {}
}

# --- Images / templates -------------------------------------------------------------

variable "cloud_images" {
  description = "VM cloud images to download onto the node, keyed by short name"
  type = map(object({
    url       = string
    file_name = string # must end in .qcow2 so Proxmox imports it correctly
  }))
  default = {}
}

variable "lxc_templates" {
  description = "LXC templates to download onto the node, keyed by short name"
  type = map(object({
    url       = string
    file_name = string
  }))
  default = {}
}

# --- Guests --------------------------------------------------------------------------

variable "vms" {
  description = "Standalone VMs, keyed by VM name"
  type = map(object({
    image              = string # key into var.cloud_images
    pool               = optional(string)
    tags               = optional(list(string), [])
    vm_id              = optional(number)
    mac_address        = optional(string)
    cores              = optional(number, 2)
    cpu_limit          = optional(number)       # fractional cpulimit (e.g. 0.5); null = unlimited
    memory             = optional(number, 2048) # MB
    disk_gb            = optional(number, 20)
    data_disk_gb       = optional(number)         # second disk for Longhorn workers
    ip                 = optional(string, "dhcp") # CIDR (192.168.68.20/24) or "dhcp"
    bridge             = optional(string)
    vlan_id            = optional(number)
    startup_order      = optional(number) # lower boots first on host start
    startup_up_delay   = optional(number) # seconds before next VM
    startup_down_delay = optional(number)
    # PCI hardware-mapping names (see var.pci_mappings); e.g. ["ai-igpu"]
    hostpci_mappings = optional(list(string), [])
    # Guest RAM hugepages: "2" | "1024" | "any" (null = off). Prefer "2" for AI VMs.
    hugepages      = optional(string)
    keep_hugepages = optional(bool, false)
    numa           = optional(bool, false) # auto-on when hugepages is set
  }))
  default = {}
}

# --- PCI passthrough (GPU / etc.) ------------------------------------------------

variable "pci_mappings" {
  description = <<-EOT
    Cluster PCI hardware mappings for VFIO passthrough (required with API-token auth).
    Example for Radeon 890M: ai-igpu id 1002:150e path 0000:c6:00.0 (verify with lspci -nn).
    Host must bind the device to vfio-pci before the guest starts — see README.
  EOT
  type = map(object({
    id           = string           # vendor:device, e.g. 1002:150e (lspci -nn)
    subsystem_id = optional(string) # SVID:SDID, e.g. 1f4c:b020 (required on newer PVE)
    path         = string           # e.g. 0000:c6:00.0
    iommu_group  = optional(number) # fill from node when known
    comment      = optional(string)
  }))
  default = {}
}

variable "containers" {
  description = "LXC containers, keyed by hostname"
  type = map(object({
    template     = string # key into var.lxc_templates
    pool         = optional(string)
    tags         = optional(list(string), [])
    vm_id        = optional(number)
    cores        = optional(number, 1)
    memory       = optional(number, 1024) # MB
    disk_gb      = optional(number, 8)
    ip           = optional(string, "dhcp")
    unprivileged = optional(bool, true)
    os_type      = optional(string, "debian") # proxmox CT OS type: debian, ubuntu, …
  }))
  default = {}
}

# --- Backups (vzdump) -------------------------------------------------------------

variable "backup_storage_enabled" {
  description = "Create backup datastore and jobs. Set false to disable without removing vars."
  type        = bool
  default     = true
}

variable "backup_storage_id" {
  description = "Proxmox datastore ID for vzdump archives. Change when migrating to PBS or external backup storage."
  type        = string
  default     = "local-backup"
}

variable "backup_storage_path" {
  description = "Host path for directory storage (must match backup_storage_id)."
  type        = string
  default     = "/var/lib/vz/backups"
}

variable "backup_notify_emails" {
  description = "Extra email addresses for backup job notifications (datacenter mailto also applies)."
  type        = list(string)
  default     = []
}

variable "backup_jobs" {
  description = <<-EOT
    Cluster backup jobs keyed by job id (Terraform resource key).
    Stage 2 migration: change backup_storage_id only — job ids and schedules stay.
  EOT
  type = map(object({
    schedule         = string
    enabled          = optional(bool, true)
    mode             = optional(string, "snapshot")
    compress         = optional(string, "zstd")
    all              = optional(bool, true)
    mailnotification = optional(string, "failure")
    prune_backups = optional(map(string), {
      "keep-daily"   = "7"
      "keep-weekly"  = "4"
      "keep-monthly" = "3"
    })
  }))
  default = {
    daily-all = {
      schedule = "*-*-* 02:00"
      all      = true
    }
  }
}
