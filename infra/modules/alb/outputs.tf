output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "zone_id" {
  value = aws_lb.this.zone_id
}

output "security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "listener_arn" {
  description = "The listener that forwards to the app (HTTPS when enabled)."
  value       = local.https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}
