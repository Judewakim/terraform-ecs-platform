locals {
  https = var.certificate_arn != null
}

# --- Security group: the only thing open to the internet ---------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public load balancer"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Public web entry point; redirects to HTTPS whenever a certificate is configured
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (redirects to HTTPS when a certificate is set)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = local.https ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Egress to the app is wired in the environment root, next to the app's
# matching ingress rule, so the two security groups don't depend on each other.

# --- Access logs -------------------------------------------------------------

data "aws_elb_service_account" "this" {}
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_18:This bucket is the log destination; logging it would recurse
  #checkov:skip=CKV_AWS_21:Logs are write-once and expire; versioning adds cost only
  #checkov:skip=CKV_AWS_144:Single-region project
  #checkov:skip=CKV2_AWS_62:No consumer for bucket events
  #checkov:skip=CKV_AWS_145:ALB access logs only support SSE-S3, not a KMS key
  count = var.access_logs_enabled ? 1 : 0

  bucket_prefix = "${var.name}-alb-logs-"
  force_destroy = var.force_destroy_logs
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ALB access logs only support SSE-S3, not a customer KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.access_log_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "logs" {
  count = var.access_logs_enabled ? 1 : 0

  statement {
    sid       = "AlbWrites"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs[0].arn,
      "${aws_s3_bucket.logs[0].arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# --- Load balancer -----------------------------------------------------------

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Deletion protection is a variable; on outside dev, off in dev so teardown works
  #checkov:skip=CKV2_AWS_28:WAF costs about $5+/mo; listed as a production upgrade in docs/decisions.md
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; ALB-to-task traffic stays inside the VPC on a security-group-locked port
  name        = "${var.name}-app"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip" # required for Fargate awsvpc networking
  vpc_id      = var.vpc_id

  # Give in-flight requests 30s to finish when a task is replaced.
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Port 80 only redirects to HTTPS when a certificate is set; HTTP-only is the no-domain dev default
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https ? "redirect" : "forward"
    target_group_arn = local.https ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
