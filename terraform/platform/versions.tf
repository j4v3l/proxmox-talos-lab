terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "talos-production-terraform-state"
    encrypt      = true
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }
}
