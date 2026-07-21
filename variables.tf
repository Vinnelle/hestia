
variable "node_ip" {
  description = "Public IP of the Talos node"
  type        = string
  default     = "51.83.199.137"
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "hestia"
}

variable "acme_email_vin_moe" {
  description = "Email for the Let's Encrypt ACME account used for vin.moe certs"
  type        = string
  default     = "a@vin.moe"
}

variable "acme_email_vinnel_cloud" {
  description = "Email for the Let's Encrypt ACME account used for vinnel.cloud certs"
  type        = string
  default     = "finlay@vinnel.cloud"
}

variable "acme_email_monke_academy" {
  description = "Email for the Let's Encrypt ACME account used for monke.academy certs"
  type        = string
  default     = "a@monke.academy"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit) for managing DNS records. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "grafana_sa_token" {
  description = "Grafana service account token, manually created in the Grafana UI. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "harbor_admin_password" {
  description = "Harbor admin password (registry.vinnel.cloud). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "s3_backup_access_key" {
  description = "Cloudflare R2 S3 access key ID for the hestia-backups bucket (create under R2 -> Manage API Tokens, scoped to this bucket). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "s3_backup_secret_key" {
  description = "Cloudflare R2 S3 secret access key for the hestia-backups bucket. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "backup_encryption_password" {
  description = "Restic repository password encrypting the pv-backup snapshots client-side before they reach R2. Set as a TFC workspace variable, not codified. CRITICAL: also keep a copy offline (with the state exports) — without it every backup is unreadable, and it cannot be recovered from R2 or TFC state loss."
  type        = string
  sensitive   = true
}

variable "netbird_api_token" {
  description = "Netbird personal access token for the netbird Terraform provider, minted once via a service user (Settings -> Service Users -> create -> generate PAT) so setup keys can be managed in code instead of by hand. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "debian_server_ssh_public_key" {
  description = "Legacy single SSH public key for the momus 'ida' user. Prefer adding keys to hestia/momus/ssh/authorized_keys (committed, supports multiple keys). Kept for compatibility and merged with that file; leave empty once your keys live in the file. Set as a TFC workspace variable, not codified."
  type        = string
  default     = ""
}
