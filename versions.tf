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
    signoz = {
      source  = "SigNoz/signoz"
      version = "~> 0.1"
    }
    restapi = {
      source  = "thegeeklab/restapi"
      version = "~> 0.3"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 19.0"
    }
  }
}
