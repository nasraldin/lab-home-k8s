# PCI hardware mappings for guest passthrough (API-token safe alternative to raw ids).

resource "proxmox_hardware_mapping_pci" "guest" {
  for_each = var.pci_mappings

  name    = each.key
  comment = coalesce(each.value.comment, "Managed by Terraform (${each.key})")

  map = [
    {
      id          = each.value.id
      node        = var.node_name
      path        = each.value.path
      iommu_group = each.value.iommu_group
    }
  ]
}
