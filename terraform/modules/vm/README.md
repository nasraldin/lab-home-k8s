# VM module (k8s-lab)

Creates one Proxmox VM from a cloud image with OVMF/q35, ballooning, and
optional second disk (`scsi1`) for Longhorn on workers.

Adapted from `terraform-lab/modules/vm` with `data_disk_gb`.
