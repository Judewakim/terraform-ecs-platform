output "app_url" {
  value = "${var.certificate_arn == null ? "http" : "https"}://${module.alb.dns_name}"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster" {
  value = module.app.cluster_name
}

output "ecs_service" {
  value = module.app.service_name
}

output "log_group" {
  value = module.app.log_group_name
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${module.observability.dashboard_name}"
}

output "nat_gateways" {
  value = length(module.network.nat_gateway_ids)
}

output "image_tag" {
  description = "Image tag from the last apply. Reuse it to plan without changing the app."
  value       = var.image_tag
}
