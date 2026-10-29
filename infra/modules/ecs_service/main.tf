data "aws_region" "current" {}

locals {
  image = "${var.repository_url}:${var.image_tag}"
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; 30 days in dev to control cost
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

# --- Security group ----------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "ECS tasks. Ingress only from the load balancer (wired in the environment root)."
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app" }
}

# Tasks need HTTPS out (through NAT) for ECR, Secrets Manager and CloudWatch Logs.
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- IAM ---------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: what ECS itself uses to start the task (pull image, write
# logs, fetch the DB secret). The app code never gets these permissions.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource scoping
  }

  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.repository_arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }

  statement {
    sid       = "DbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid       = "DecryptSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "start-task"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# Task role: what the running app can call. It needs no AWS APIs today, so it
# gets no policy. Add statements here only when the app needs them.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# --- Task definition ---------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = "app"
      image                  = local.image
      essential              = true
      readonlyRootFilesystem = true
      user                   = "10001"
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      environment = [
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "APP_VERSION", value = var.image_tag },
        { name = "LOG_LEVEL", value = "INFO" },
      ]
      # Pulled from Secrets Manager at task start. Never stored in the task definition.
      secrets = [
        { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
        }
      }
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])
}

# --- Service -----------------------------------------------------------------

# ECS rejects a target group that isn't attached to a listener yet. This node
# makes the service wait for the listener without a module-wide depends_on.
resource "terraform_data" "listener_ready" {
  input = var.listener_arn
}

resource "aws_ecs_service" "app" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.min_tasks
  launch_type     = "FARGATE"

  # Rolling deploy: keep full capacity up, and roll back automatically if new
  # tasks fail health checks.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 30
  enable_execute_command            = false
  propagate_tags                    = "SERVICE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # Autoscaling owns the task count after creation.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [terraform_data.listener_ready]
}

# --- Autoscaling -------------------------------------------------------------

resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_task_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${var.target_group_arn_suffix}"
    }
  }
}
