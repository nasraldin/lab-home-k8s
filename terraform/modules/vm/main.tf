resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id
  pool_id   = var.pool_id
  tags      = var.tags

  # Proxmox VE 9 lab standard — match terraform-lab / hub vm-best-practices
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0", "net0"]

  started         = var.started
  on_boot         = true
  stop_on_destroy = true

  dynamic "startup" {
    for_each = var.startup_order != null ? [1] : []
    content {
      order      = tostring(var.startup_order)
      up_delay   = tostring(coalesce(var.startup_up_delay, 0))
      down_delay = tostring(coalesce(var.startup_down_delay, 0))
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  cpu {
    cores   = var.cores
    sockets = 1
    type    = "host"
    limit   = var.cpu_limit
    # Hugepages require NUMA (Proxmox / bpg).
    numa = var.numa || var.hugepages != null
  }

  memory {
    dedicated = var.memory
    # Ballooning conflicts with hugepages — force fixed RAM when hugepages are set.
    floating = var.hugepages != null ? 0 : var.memory
    # hugepages / keep_hugepages require root@pam on Proxmox. Terraform API tokens
    # (terraform@pve) cannot set them — apply via: qm set <vmid> --hugepages 2
    # and leave managed outside TF (see lifecycle ignore_changes below).
    hugepages      = var.hugepages
    keep_hugepages = var.hugepages != null ? var.keep_hugepages : null
  }

  # Non-root API tokens get HTTP 500 "only root can set 'hugepages' config" on
  # any memory update that touches these fields. Manage hugepages out-of-band.
  lifecycle {
    ignore_changes = [
      memory[0].hugepages,
      memory[0].keep_hugepages,
    ]
  }

  efi_disk {
    datastore_id = var.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = var.image_file_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    cache        = "none"
    size         = var.disk_gb
  }

  dynamic "disk" {
    for_each = var.data_disk_gb != null ? [var.data_disk_gb] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      iothread     = true
      discard      = "on"
      ssd          = true
      cache        = "none"
      size         = disk.value
      file_format  = "raw"
    }
  }

  dynamic "hostpci" {
    for_each = { for i, h in var.hostpci : i => h }
    content {
      device  = "hostpci${hostpci.key}"
      mapping = hostpci.value.mapping
      pcie    = hostpci.value.pcie
      rombar  = hostpci.value.rombar
      xvga    = hostpci.value.xvga
    }
  }

  network_device {
    bridge      = var.bridge
    model       = "virtio"
    mac_address = var.mac_address
    vlan_id     = var.vlan_id
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "std"
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.ip_address == "dhcp" ? null : var.gateway
      }
    }

    vendor_data_file_id = var.vendor_data_file_id

    user_account {
      username = var.username
      keys     = var.ssh_keys
    }
  }
}
