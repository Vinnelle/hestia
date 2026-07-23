terraform {
  required_version = ">= 1.9.0"

  cloud {
    organization = "lover"
    workspaces {
      name = "hestia"
    }
  }
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.39"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = "~> 0.0"
    }
  }
}
