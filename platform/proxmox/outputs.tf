output "disk_serials" {
  description = "Serial of each Talos VM disk (virtio-blk, so Talos reads it as disk.serial), keyed by role"
  value = {
    system = local.disks.virtio0.serial
    hdd1   = local.disks.virtio1.serial
    hdd2   = local.disks.virtio2.serial
    ssd    = local.disks.virtio3.serial
  }
}

output "pbs_encryption_key" {
  description = "Key Proxmox VE encrypts every VM backup with before it reaches PBS; keep a copy offline, because without it no backup can be restored"
  value       = var.pbs_encryption_key != "" ? var.pbs_encryption_key : one(proxmox_storage_pbs.mega[*].generated_encryption_key)
  sensitive   = true
}
