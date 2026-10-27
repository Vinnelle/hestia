variable "node_name" {
  description = "Proxmox VE node name -- the hostname given at install"
  type        = string
}

variable "lan_cidr" {
  description = "Home LAN subnet; the host's firewall admits SSH and the Proxmox VE and PBS web UIs from it alone"
  type        = string
}

variable "talos_iso_url" {
  description = "Talos Image Factory Secure Boot ISO for the node's schematic and version"
  type        = string
}

variable "talos_iso_sha256" {
  description = "SHA-256 of the ISO at talos_iso_url, pinned because its Secure Boot keys are what the VM enrolls; a different file fails the download"
  type        = string
}

variable "talos_version" {
  description = "Talos version the ISO is built for, used in its file name on the host"
  type        = string
}

variable "cores" {
  description = "vCPUs for the Talos VM -- the host has 16 threads and keeps 4"
  type        = number
  default     = 12
}

variable "memory_mb" {
  description = "RAM for the Talos VM -- the passed-through GPU pins all of it, so the rest of the host's 32 GB has to cover QEMU, Proxmox, PBS, the 2 GiB ZFS ARC and the kernel's reserve"
  type        = number
  default     = 22528
}

variable "mac_address" {
  description = "Fixed MAC of the Talos VM's NIC, so the router's DHCP reservation for node_ip can exist before the VM does"
  type        = string
  default     = "02:68:65:73:74:69"
}

variable "pbs_username" {
  description = "Proxmox Backup Server API token ID Proxmox VE logs in with (e.g. pve@pbs!pve); empty until PBS is installed"
  type        = string
  default     = ""
}

variable "pbs_password" {
  description = "Secret of pbs_username's API token; while empty, the PBS storage and the backup job are not created"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pbs_encryption_key" {
  description = "Existing PBS encryption key to reuse, e.g. when rebuilding the host to restore old backups; empty generates a new one"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pbs_fingerprint" {
  description = "SHA-256 fingerprint of PBS's self-signed certificate (Dashboard -> Show Fingerprint)"
  type        = string
  default     = ""
}
