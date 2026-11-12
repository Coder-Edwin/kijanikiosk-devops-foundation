output "staging_namespace" {
  description = "Namespace the pipeline deploys staging releases into."
  value       = kubernetes_namespace_v1.staging.metadata[0].name
}

output "staging_quota" {
  description = "Hard resource ceiling applied to staging."
  value       = kubernetes_resource_quota_v1.staging.spec[0].hard
}
