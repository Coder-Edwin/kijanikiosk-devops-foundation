locals {
  common_labels = {
    "app.kubernetes.io/part-of"    = "kijanikiosk"
    "app.kubernetes.io/managed-by" = "terraform"
    "kijanikiosk.io/environment"   = "staging"
  }
}

# The staging environment: a namespace isolated from production (default).
resource "kubernetes_namespace_v1" "staging" {
  metadata {
    name   = var.staging_namespace
    labels = local.common_labels
    annotations = {
      "kijanikiosk.io/owner"   = "platform"
      "kijanikiosk.io/purpose" = "Pre-production environment; every release is smoke-tested here before the production approval gate."
    }
  }
}

# Staging can never starve production of cluster resources: a hard ceiling on
# what all staging workloads together may request and use.
resource "kubernetes_resource_quota_v1" "staging" {
  metadata {
    name      = "staging-quota"
    namespace = kubernetes_namespace_v1.staging.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    hard = {
      "requests.cpu"    = var.staging_quota.requests_cpu
      "requests.memory" = var.staging_quota.requests_memory
      "limits.cpu"      = var.staging_quota.limits_cpu
      "limits.memory"   = var.staging_quota.limits_memory
      "pods"            = var.staging_quota.pods
    }
  }
}

# Defaults for any container that forgets to declare its own requests/limits,
# so the quota above can always be enforced.
resource "kubernetes_limit_range_v1" "staging" {
  metadata {
    name      = "staging-container-defaults"
    namespace = kubernetes_namespace_v1.staging.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "250m"
        memory = "128Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "64Mi"
      }
    }
  }
}
