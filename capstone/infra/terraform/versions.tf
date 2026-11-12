terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0, < 4.0.0"
    }
  }
}

# Talks to the local minikube cluster through the engineer's kubeconfig.
# No credentials are stored in this repository.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}
