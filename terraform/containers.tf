resource "proxmox_virtual_environment_container" "ct" {
  for_each = var.containers

  # Prefer VMs for Docker/K8s/GitLab.
  node_name    = var.node_name
  vm_id        = each.value.vm_id
  pool_id      = each.value.pool
  tags         = each.value.tags
  unprivileged = each.value.unprivileged

  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = proxmox_download_file.lxc_template[each.value.template].id
    type             = each.value.os_type
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_datastore
    size         = each.value.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.ip == "dhcp" ? null : var.network_gateway
      }
    }

    user_account {
      # LXC schema has keys/password only (no username) — keys land on root.
      # Ansible dockhand host uses ansible_user: root (see host_vars/dockhand.yml).
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  dynamic "device_passthrough" {
    for_each = { for i, d in each.value.device_passthrough : i => d }
    content {
      path = device_passthrough.value.path
      uid  = try(device_passthrough.value.uid, null)
      gid  = try(device_passthrough.value.gid, null)
      mode = try(device_passthrough.value.mode, "0666")
    }
  }

  depends_on = [
    proxmox_virtual_environment_pool.pool,
    proxmox_node_disk_zfs.pool,
  ]

  # Debian 13 / systemd 257 in unprivileged CT needs nesting for Docker-ish stacks.
  # Privileged containers: API tokens cannot set feature flags (root@pam only) — skip nesting.
  dynamic "features" {
    for_each = each.value.unprivileged ? [1] : []
    content {
      nesting = true
    }
  }

  # Privileged CTs (device passthrough / features) must be set as root@pam; ignore API drift.
  lifecycle {
    ignore_changes = [
      features,
      initialization, # ssh keys / cloud-init not always readable after pct create
      operating_system[0].template_file_id,
      network_interface[0].mac_address,
    ]
  }
}
