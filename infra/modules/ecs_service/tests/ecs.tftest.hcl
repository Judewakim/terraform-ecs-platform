mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
}

variables {
  name                     = "test"
  vpc_id                   = "vpc-123"
  app_subnet_ids           = ["subnet-a", "subnet-b"]
  repository_url           = "123456789012.dkr.ecr.us-east-1.amazonaws.com/shortlink"
  repository_arn           = "arn:aws:ecr:us-east-1:123456789012:repository/shortlink"
  image_tag                = "abc1234"
  target_group_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/t/1"
  target_group_arn_suffix  = "targetgroup/t/1"
  alb_arn_suffix           = "app/t/1"
  listener_arn             = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/t/1/2"
  db_host                  = "db.internal"
  db_port                  = 5432
  db_name                  = "shortlink"
  db_secret_arn            = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-mock"
  kms_key_arn              = "arn:aws:kms:us-east-1:123456789012:key/mock"
  logs_kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/mock"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/shortlink-workload-boundary"
}

run "tasks_are_private" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.app.network_configuration).assign_public_ip == false
    error_message = "Tasks must not get public IPs."
  }
}

run "container_hardening" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Root filesystem must be read-only."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].user == "10001"
    error_message = "Container must run as a non-root user."
  }
  assert {
    condition = alltrue([
      for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment :
      !contains(["DB_PASSWORD", "DB_USER"], e.name)
    ])
    error_message = "Credentials must come from Secrets Manager, not plain environment variables."
  }
}

run "deploys_roll_back_on_failure" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.app.deployment_circuit_breaker).rollback
    error_message = "Failed deployments must roll back automatically."
  }
  assert {
    condition     = aws_ecs_service.app.deployment_minimum_healthy_percent == 100
    error_message = "Deploys must keep full capacity running."
  }
}

run "app_role_reads_only_its_secret" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment[index(jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment[*].name, "DB_SECRET_ARN")].value == var.db_secret_arn
    error_message = "The app must be told which secret to read."
  }
  assert {
    condition     = aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn
    error_message = "Task role must carry the permissions boundary."
  }
}
