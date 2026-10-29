output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "security_group_id" {
  value = aws_security_group.app.id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
