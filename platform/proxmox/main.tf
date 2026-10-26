locals {
  disks = {
    virtio0 = { serial = "hestia-system", size = 128 }
    virtio1 = { serial = "hestia-hdd1", size = 600 }
    virtio2 = { serial = "hestia-hdd2", size = 600 }
    virtio3 = { serial = "hestia-ssd", size = 200 }
  }

  gpu = jsondecode(file("${path.module}/gpu.json"))
}

resource "proxmox_apt_standard_repository" "no_subscription" {
  node   = var.node_name
  handle = "no-subscription"
}

resource "proxmox_apt_repository" "enterprise" {
  node      = var.node_name
  file_path = "/etc/apt/sources.list.d/pve-enterprise.sources"
  index     = 0
  enabled   = false
}

resource "proxmox_apt_repository" "ceph_enterprise" {
  node      = var.node_name
  file_path = "/etc/apt/sources.list.d/ceph.sources"
  index     = 0
  enabled   = false
}

resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "host" {
  node_name = var.node_name

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = var.lan_cidr
    proto   = "tcp"
    dport   = "22"
    comment = "SSH from the LAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = var.lan_cidr
    proto   = "tcp"
    dport   = "8006"
    comment = "Proxmox VE web UI and API from the LAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = var.lan_cidr
    proto   = "tcp"
    dport   = "8007"
    comment = "Proxmox Backup Server web UI and API from the LAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = var.lan_cidr
    macro   = "Ping"
    comment = "ICMP echo from the LAN"
  }
}

resource "proxmox_storage_zfspool" "vault" {
  id             = "vault"
  zfs_pool       = "vault"
  content        = ["images"]
  thin_provision = true
  nodes          = [var.node_name]
}

resource "proxmox_download_file" "talos_iso" {
  node_name          = var.node_name
  datastore_id       = "local"
  content_type       = "iso"
  url                = var.talos_iso_url
  file_name          = "talos-${var.talos_version}-secureboot.iso"
  checksum           = var.talos_iso_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 1800
}

resource "proxmox_hardware_mapping_pci" "gpu" {
  name    = local.gpu.mapping
  comment = "RTX 4070 Ti and its HDMI audio function, passed through to the Talos VM"
  map = [{
    node         = var.node_name
    path         = local.gpu.path
    id           = local.gpu.id
    subsystem_id = local.gpu.subsystem_id
    iommu_group  = local.gpu.iommu_group
  }]
}

resource "proxmox_virtual_environment_vm" "hestia" {
  node_name           = var.node_name
  vm_id               = 100
  name                = "hestia"
  description         = "Talos node, managed by Terraform (hestia/platform/proxmox)"
  tags                = ["gaia"]
  machine             = "q35"
  bios                = "ovmf"
  on_boot             = false
  started             = true
  protection          = true
  stop_on_destroy     = true
  reboot_after_update = false
  boot_order          = ["virtio0", "ide2"]

  agent {
    enabled = true
  }

  cpu {
    type  = "host"
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    floating  = 0
  }

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = proxmox_storage_zfspool.vault.id
    type              = "4m"
    file_format       = "raw"
    pre_enrolled_keys = false
  }

  tpm_state {
    datastore_id = proxmox_storage_zfspool.vault.id
    version      = "v2.0"
  }

  dynamic "disk" {
    for_each = local.disks
    content {
      interface    = disk.key
      datastore_id = proxmox_storage_zfspool.vault.id
      file_format  = "raw"
      size         = disk.value.size
      serial       = disk.value.serial
      discard      = "on"
      iothread     = true
    }
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  hostpci {
    device  = "hostpci0"
    mapping = proxmox_hardware_mapping_pci.gpu.name
    pcie    = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = var.mac_address
  }
}

resource "proxmox_storage_pbs" "mega" {
  count = var.pbs_password == "" ? 0 : 1

  id                      = "mega"
  server                  = "127.0.0.1"
  datastore               = "mega"
  username                = var.pbs_username
  password                = var.pbs_password
  fingerprint             = var.pbs_fingerprint
  content                 = ["backup"]
  encryption_key          = var.pbs_encryption_key == "" ? null : var.pbs_encryption_key
  generate_encryption_key = var.pbs_encryption_key == "" ? true : null
  nodes                   = [var.node_name]
}

resource "proxmox_backup_job" "hestia" {
  count = length(proxmox_storage_pbs.mega)

  id       = "hestia-nightly"
  schedule = "03:00"
  storage  = proxmox_storage_pbs.mega[0].id
  vmid     = [tostring(proxmox_virtual_environment_vm.hestia.vm_id)]
  mode     = "snapshot"
  enabled  = true
  fleecing = {
    enabled = true
    storage = proxmox_storage_zfspool.vault.id
  }
  prune_backups = {
    keep-daily  = "7"
    keep-weekly = "4"
  }
}
