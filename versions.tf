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
      version = "~> 0.12"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = "~> 0.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 19.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    linode = {
      source  = "linode/linode"
      version = "~> 4.7"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = "~> 0.4"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.118"
    }
  }
}
