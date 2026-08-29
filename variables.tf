
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

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit) for managing DNS records. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "cloudflare_cache_purge_token" {
  description = "Cloudflare API token (Zone:Zone:Read, Zone:Cache Purge:Purge) used by .gitlab-ci.yml's site-deploy jobs to purge the CDN cache after a rollout -- deliberately separate from cloudflare_api_token, which only carries DNS:Edit and is not scoped for cache purging. Same split the original .github/workflows/site-deploy.yml already had (a dedicated CLOUDFLARE_API_TOKEN Actions secret, distinct from whatever token Terraform itself used) -- can be minted fresh or reuse that secret's value if still known. Set as a TFC workspace variable, not codified."
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

variable "mega_import_user" {
  description = "MEGA.nz account email for the one-time nextcloud-mega-import job that pulls the user's existing MEGA drive into Nextcloud. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "mega_import_pass" {
  description = "MEGA.nz account password paired with mega_import_user. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "resend_api_key" {
  description = "Resend API key used as the SMTP password for outbound mail (GitLab notifications etc.), authenticated as alerts@vinnel.cloud via the mail.vinnel.cloud DNS records. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
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

variable "signoz_api_token" {
  description = "SigNoz API access token, manually created in the SigNoz UI (Settings -> API Keys). Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "gitlab_api_token" {
  description = "GitLab Personal/Admin Access Token (api scope), minted by hand as root at https://gitlab.vinnel.cloud once GitLab itself is up (two-apply bootstrap: GitLab has to exist before it can mint its own token). Used by the gitlab Terraform provider. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "gitlab_mirror_github_pat" {
  description = "GitHub PAT with push access to Vinnelle/gaia, hestia, love, vin.moe -- used by .gitlab-ci.yml's outbound mirror jobs to keep GitHub in sync as gaia's backup/public-mirror source now that GitLab is canonical. Same scope as the existing GH_API_TOKEN GitHub Actions secret; can be the same value or a freshly minted one. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "gitlab_tfc_api_token" {
  description = "Terraform Cloud API token (org 'lover', workspace 'hestia') -- same value as the TFC_API_TOKEN GitHub Actions secret terraform.yml already uses, threaded into GitLab CI/CD as TF_TOKEN_app_terraform_io (Terraform CLI's own env-var convention for per-host credentials, needs no extra scripting to be picked up). Set as a TFC workspace variable, not codified -- yes, a TFC token stored as a TFC workspace variable so CI can authenticate back to TFC; the two are separate stores with no other bridge."
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

variable "satisfactory_admin_password" {
  description = "Admin password set by hand through the Satisfactory Server Manager UI when the server was claimed. Used by admin.vinnel.cloud's Satisfactory console to PasswordLogin for an Administrator token before each RunCommand. Set as a TFC workspace variable, not codified. Leave empty to fall back to PasswordlessLogin, which only works on an unclaimed server."
  type        = string
  sensitive   = true
  default     = ""
}

variable "docker_hub_username" {
  description = "Docker Hub account used solely to authenticate gitlab_group_dependency_proxy.vinnel_cloud's upstream pull-through connection -- never exposed to CI, never stored as a GitLab/GitHub secret. Anonymous proxy pulls share the node's egress IP with every other anonymous Docker Hub client on this host and hit the same per-IP rate limit as a direct anonymous pull would; an authenticated free account gets its own per-account limit instead. Mint/reuse a free Docker Hub account and set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token (Account Settings -> Security -> Personal access tokens, Public Repo Read-only scope is enough) paired with docker_hub_username. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}

variable "glitchtip_api_token" {
  description = "GlitchTip API token created under Profile -> Auth Tokens, used to provision the gaia project and its ingestion key. Set as a TFC workspace variable, not codified."
  type        = string
  sensitive   = true
}
