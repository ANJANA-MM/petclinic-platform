output "name_prefix" {
  description = "Resource name prefix (petclinic-{env})"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Tags applied to all resources via provider default_tags"
  value       = local.common_tags
}
