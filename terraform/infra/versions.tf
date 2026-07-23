terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "talos-production-terraform-state"
    encrypt      = true
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.107"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
  }
}
