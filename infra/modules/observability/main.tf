data "aws_region" "current" {}

# --- Alert routing -------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS emails a confirm link; alerts start after you click it
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  alb_dims      = { LoadBalancer = var.alb_arn_suffix }
  tg_dims       = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  ecs_dims      = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  db_dims       = { DBInstanceIdentifier = var.db_identifier }
}

# --- Alarms: the four things that mean users are hurting -----------------------

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name}-app-5xx"
  alarm_description   = "App returned 5xx errors. Runbook: docs/runbook.md#app-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.tg_dims
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.error_threshold_per_minute
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-unhealthy-tasks"
  alarm_description   = "A task is failing load balancer health checks. Runbook: docs/runbook.md#unhealthy-tasks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-latency-p95"
  alarm_description   = "p95 response time is high. Runbook: docs/runbook.md#high-latency"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.tg_dims
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.latency_p95_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.name}-ecs-cpu-high"
  alarm_description   = "Service CPU stays high even after autoscaling. Runbook: docs/runbook.md#high-cpu"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dims
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 8
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name}-db-cpu-high"
  alarm_description   = "Database CPU is high. Runbook: docs/runbook.md#database"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.db_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.name}-db-storage-low"
  alarm_description   = "Database free storage under 2 GB. Runbook: docs/runbook.md#database"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = local.db_dims
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Dashboard ------------------------------------------------------------------

locals {
  region = data.aws_region.current.region

  widgets = [
    {
      title = "Requests and errors (per minute)"
      metrics = [
        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Requests" }],
        ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Sum", label = "App 5xx", color = "#d62728" }],
        ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "ALB 5xx", color = "#ff7f0e" }],
      ]
    },
    {
      title = "Response time (seconds)"
      metrics = [
        ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p50", label = "p50" }],
        ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p95", label = "p95" }],
      ]
    },
    {
      title = "Healthy vs unhealthy tasks"
      metrics = [
        ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Minimum", label = "Healthy" }],
        ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Maximum", label = "Unhealthy", color = "#d62728" }],
      ]
    },
    {
      title = "ECS service CPU and memory (%)"
      metrics = [
        ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average", label = "CPU" }],
        ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average", label = "Memory" }],
      ]
    },
    {
      title = "Database CPU (%) and connections"
      metrics = [
        ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier, { stat = "Average", label = "CPU" }],
        ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier, { stat = "Maximum", label = "Connections", yAxis = "right" }],
      ]
    },
    {
      title = "Database free storage (bytes)"
      metrics = [
        ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_identifier, { stat = "Minimum", label = "Free storage" }],
      ]
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      for i, w in local.widgets : {
        type   = "metric"
        x      = (i % 2) * 12
        y      = floor(i / 2) * 6
        width  = 12
        height = 6
        properties = {
          title   = w.title
          region  = local.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = w.metrics
        }
      }
    ]
  })
}

# --- Cost guard -------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  count = var.alert_email == null ? 0 : 1

  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project_tag)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
