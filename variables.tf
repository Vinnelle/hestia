
variable "node_ip" {
  description = "Public IP of the Talos node"
  type        = string
  default     = "146.59.54.33"
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

variable "harbor_admin_password" {
  description = "Harbor admin password (registry.vinnel.cloud). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "s3_backup_access_key" {
  description = "S3-compatible access key ID for the gaia-backups bucket. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "s3_backup_endpoint" {
  description = "S3-compatible endpoint hosting the gaia-backups bucket."
  type        = string
  default     = "gaia-backups.s3.g.megas4.com"
}

variable "s3_backup_secret_key" {
  description = "S3-compatible secret access key for the gaia-backups bucket. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "mega_s4_access_key" {
  description = "MEGA S4 access key ID dedicated to Velero's own 'velero' bucket, minted by hand via MEGA's Object Storage -> Keys page (S4's IAM API has no CreateUser/CreateAccessKey endpoint, only policy attach/detach on already-existing users -- see github.com/meganz/s4-specs). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "mega_s4_secret_key" {
  description = "MEGA S4 secret access key paired with mega_s4_access_key. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "mega_s4_endpoint_domain" {
  description = "MEGA S4 <endpoint_domain> for this account -- the S3 API lives at s3.<this>, IAM API at iam.<this>, per github.com/meganz/s4-specs. Matches the domain suffix already used in s3_backup_endpoint's default."
  type        = string
  default     = "g.megas4.com"
}

variable "backup_encryption_password" {
  description = "Restic repository password encrypting the pv-backup snapshots client-side before they reach the bucket. Set as a TFC workspace variable, not codified. CRITICAL: also keep a copy offline (with the state exports) — without it every backup is unreadable, and it cannot be recovered from bucket or TFC state loss."
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

variable "gh_app_id" {
  description = "App ID of the GitHub App installed on Vinnelle/gaia for actions-runner-controller. Not secret (visible in the GitHub App's UI), but set as a TFC workspace variable to keep it alongside the other GH App vars."
  type        = string
}

variable "gh_app_installation_id" {
  description = "Installation ID of the GitHub App on Vinnelle/gaia for actions-runner-controller. Not secret (visible in the installation URL), but set as a TFC workspace variable to keep it alongside the other GH App vars."
  type        = string
}

variable "gh_app_private_key" {
  description = "PEM private key of the GitHub App used by actions-runner-controller to mint runner registration tokens. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "signoz_api_token" {
  description = "SigNoz API access token, manually created in the SigNoz UI (Settings -> API Keys). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "minecraft_modpack_zip_url" {
  description = "URL the fetch-modpack init container downloads the Create: Ultimate Selection 2 client zip from. Required because the modpack's authors set allowModDistribution=false, so the CurseForge API refuses to serve the pack archive and it has to be downloaded by hand once and self-hosted. Any URL the cluster can reach works (seaweedfs/S3 presigned, a GitHub release asset, momus). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "curseforge_api_key" {
  description = "CurseForge Eternal API key, minted at https://console.curseforge.com/ (Account -> API Keys), used by the itzg/minecraft-server image's AUTO_CURSEFORGE installer to resolve and download the modpack. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}
