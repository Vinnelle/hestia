
variable "node_ip" {
  description = "LAN IP of the Talos VM -- reserve it on the home router for the VM's fixed MAC (platform/proxmox mac_address), since nothing else pins it"
  type        = string
}

variable "proxmox_endpoint" {
  description = "Proxmox VE API on the LAN, e.g. https://192.168.1.2:8006/. Its certificate is self-signed, so the provider skips verification."
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE API token Terraform manages the host and the Talos VM with, as terraform@pve!gaia=<secret> (Bootstrap step 5). Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox VE node name -- the hostname given at install"
  type        = string
  default     = "pve"
}

variable "pbs_username" {
  description = "Proxmox Backup Server API token ID Proxmox VE logs in with, e.g. pve@pbs!pve (Bootstrap step 15)"
  type        = string
  default     = ""
}

variable "pbs_password" {
  description = "Secret of pbs_username's API token; while empty, Terraform creates no PBS storage or backup job. Set in secrets.sops.json."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pbs_encryption_key" {
  description = "Existing PBS encryption key to reuse (terraform output -raw pbs_encryption_key, from before) when rebuilding the host to restore old backups; empty generates a new one. Set in secrets.sops.json."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pbs_fingerprint" {
  description = "SHA-256 fingerprint of PBS's self-signed certificate (PBS Dashboard -> Show Fingerprint)"
  type        = string
  default     = ""
}

variable "lan_cidr" {
  description = "Home LAN subnet the Talos VM sits on. The node firewall admits the Kubernetes and Talos APIs, the web ports and the relayed game ports from it."
  type        = string
}

variable "linode_token" {
  description = "Linode personal access token scoped to Object Storage (read/write), used to manage the object storage buckets. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "linode_region" {
  description = "Linode region the Object Storage buckets live in. Frankfurt 2: Germany's courts and data-retention rulings make it the most private jurisdiction Linode offers"
  type        = string
  default     = "de-fra-2"
}

variable "mega_s4_endpoint_domain" {
  description = "MEGA S4 endpoint domain the backup buckets are created behind (the S3 API is s3.<this>, the signing region its first label). Luxembourg: EU law, and outside the Five and Fourteen Eyes, unlike MEGA's Amsterdam, Paris, Barcelona and Canadian sites"
  type        = string
  default     = "eu-luxembourg-1.megas4.com"
}

variable "mega_s4_access_key" {
  description = "Access key of the MEGA S4 user Terraform manages the buckets with. That user holds only S3BucketReadAccess, S3BucketWriteAccess and S3ObjectListAccess, so nothing holding this key (CI included) can delete a backup. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "mega_s4_secret_key" {
  description = "Secret key of that MEGA S4 user. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "mega_import_access_key" {
  description = "Access key of the MEGA S4 user the Nextcloud import job reads hestia-import with; it holds only S3ObjectReadAccess. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "mega_import_secret_key" {
  description = "Secret key of that MEGA S4 user. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "infomaniak_auth_url" {
  description = "Keystone endpoint of Infomaniak Public Cloud, the same for every region"
  type        = string
  default     = "https://api.pub1.infomaniak.cloud/identity"
}

variable "infomaniak_region" {
  description = "Infomaniak Public Cloud region the relay runs in. dc3-a is Infomaniak's Geneva data centre, under Swiss law"
  type        = string
  default     = "dc3-a"
}

variable "infomaniak_application_credential_id" {
  description = "ID of an application credential on the Infomaniak Public Cloud project, with the member and reader roles, used to build the relay and upload its image. Set in secrets.sops.json."
  type        = string
}

variable "infomaniak_application_credential_secret" {
  description = "Secret of that application credential. Set in secrets.sops.json."
  type        = string
  sensitive   = true
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
  description = "Cloudflare API token for DNS records, zone settings and Universal SSL: Zone:DNS:Edit, Zone:Zone Settings:Edit and Zone:SSL and Certificates:Edit. Cloudflare only serves DNS -- nothing is proxied through it. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}
variable "resend_api_key" {
  description = "Resend API key used as the SMTP password for outbound mail (GitLab notifications etc.), authenticated as alerts@vinnel.cloud via the mail.vinnel.cloud DNS records. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "netbird_api_token" {
  description = "Netbird personal access token for the netbird Terraform provider, minted once via a service user (Settings -> Service Users -> create -> generate PAT) so setup keys can be managed in code instead of by hand. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}
variable "gitlab_api_token" {
  description = "GitLab Personal/Admin Access Token (api scope), minted by hand as root at https://gitlab.vinnel.cloud once GitLab itself is up (two-apply bootstrap: GitLab has to exist before it can mint its own token). Used by the gitlab Terraform provider. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "gitlab_mirror_github_pat" {
  description = "GitHub PAT with push access to Vinnelle/gaia, hestia, love, vin.moe -- used by .gitlab-ci.yml's outbound mirror jobs to keep GitHub in sync as gaia's backup/public-mirror source now that GitLab is canonical. Same scope as the existing GH_API_TOKEN GitHub Actions secret; can be the same value or a freshly minted one. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "gitlab_tfc_api_token" {
  description = "HCP Terraform API token (org 'lover', workspace 'hestia'), threaded into GitLab CI/CD as TF_TOKEN_app_terraform_io (Terraform CLI's own env-var convention for per-host credentials) so CI's local-execution runs can read and write the workspace state. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "gitlab_ci_age_key" {
  description = "Private half of CI's post-quantum age key (AGE-SECRET-KEY-PQ-1...), the second recipient in .sops.yaml, published to GitLab CI/CD as the hidden SOPS_AGE_KEY so CI can decrypt secrets.sops.json. Kept in secrets.sops.json itself."
  type        = string
  sensitive   = true
}

variable "docker_hub_username" {
  description = "Docker Hub account used solely to authenticate gitlab_group_dependency_proxy.vinnel_cloud's upstream pull-through connection -- never exposed to CI, never stored as a GitLab/GitHub secret. Anonymous proxy pulls share the node's egress IP with every other anonymous Docker Hub client on this host and hit the same per-IP rate limit as a direct anonymous pull would; an authenticated free account gets its own per-account limit instead. Mint/reuse a free Docker Hub account and set it in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token (Account Settings -> Security -> Personal access tokens, Public Repo Read-only scope is enough) paired with docker_hub_username. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "gemma_sign_password" {
  description = "128-character password Gemma's chat signing identity (an AGE key) is made from, with gemma_machine_id; changing either gives her a new fingerprint. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "gemma_machine_id" {
  description = "Machine id (32 hex digits) mounted as /etc/machine-id in Gemma's pod, which chat makes her signing identity with. Set in secrets.sops.json."
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Address Alertmanager mails alerts to, from alerts@vinnel.cloud through Resend"
  type        = string
  default     = "finlay@vinnel.cloud"
}
