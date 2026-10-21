provider "talos" {}

provider "kubernetes" {
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
}

provider "kubectl" {
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  load_config_file       = false
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "tls" {}

provider "wireguard" {}

provider "linode" {
  token = var.linode_token
}

provider "openstack" {
  auth_url                      = var.infomaniak_auth_url
  region                        = var.infomaniak_region
  application_credential_id     = var.infomaniak_application_credential_id
  application_credential_secret = var.infomaniak_application_credential_secret
}

provider "aws" {
  alias  = "mega_s4"
  region = split(".", var.mega_s4_endpoint_domain)[0]

  access_key = var.mega_s4_access_key
  secret_key = var.mega_s4_secret_key

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3 = "https://s3.${var.mega_s4_endpoint_domain}"
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

provider "netbird" {
  management_url = "https://proxy.vinnel.cloud"
  token          = var.netbird_api_token
}
provider "gitlab" {
  base_url = "https://gitlab.vinnel.cloud/api/v4/"
  token    = var.gitlab_api_token
}
