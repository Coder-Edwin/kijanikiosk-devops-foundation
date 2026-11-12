variable "kubeconfig_path" {
  description = "Path to the kubeconfig that can reach the target cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Pinned so Terraform can never act on the wrong cluster."
  type        = string
  default     = "minikube"
}

variable "staging_namespace" {
  description = "Name of the staging namespace."
  type        = string
  default     = "kijani-staging"
}

variable "staging_quota" {
  description = "Hard resource ceiling for everything running in staging."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = string
  })
  default = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "2Gi"
    pods            = "10"
  }
}
