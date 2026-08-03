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

provider "harbor" {
  url      = "https://registry.vinnel.cloud"
  username = "admin"
  password = var.harbor_admin_password
}

provider "tls" {}

provider "netbird" {
  management_url = "https://proxy.vinnel.cloud"
  token          = var.netbird_api_token
}

provider "signoz" {
  endpoint     = "https://signoz.vinnel.cloud"
  access_token = var.signoz_api_token
}

provider "aws" {
  alias  = "mega_s4"
  region = "us-east-1"

  access_key = var.mega_s4_access_key
  secret_key = var.mega_s4_secret_key

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "https://s3.${var.mega_s4_endpoint_domain}"
  }
}

provider "restapi" {
  endpoint = "https://signoz.vinnel.cloud"
  headers = {
    "SIGNOZ-API-KEY" = var.signoz_api_token
    "Content-Type"   = "application/json"
  }
  create_method  = "POST"
  update_method  = "PUT"
  destroy_method = "DELETE"

  create_returns_object = true
  id_attribute          = "data/id"
}
