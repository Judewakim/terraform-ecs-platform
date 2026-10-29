locals {
  name = "${var.project}-${var.environment}"

  # Created by infra/bootstrap. The deploy role can only create roles that carry it.
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-workload-boundary"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- One customer-managed key for this environment ----------------------------
# Encrypts the database, its password secret, log groups and the alert topic.

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_111:Key policies always use Resource "*", which means this key only
  #checkov:skip=CKV_AWS_356:Key policies always use Resource "*", which means this key only
  #checkov:skip=CKV_AWS_109:Root-account statement is the AWS default that lets IAM policies govern the key
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }

  # CloudWatch alarms publish to the encrypted SNS topic.
  statement {
    sid       = "CloudWatchAlarmsToSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "${local.name} data, secrets, logs and alerts"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# --- Modules ----------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  logs_kms_key_arn   = aws_kms_key.main.arn

  permissions_boundary_arn = local.permissions_boundary_arn
}

module "ecr" {
  source = "../../modules/ecr"

  name         = var.project
  force_delete = var.environment == "dev"
}

module "alb" {
  source = "../../modules/alb"

  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  certificate_arn     = var.certificate_arn
  deletion_protection = var.environment != "dev"
  force_destroy_logs  = var.environment == "dev"
}

module "database" {
  source = "../../modules/database"

  name                = local.name
  vpc_id              = module.network.vpc_id
  db_subnet_ids       = module.network.db_subnet_ids
  kms_key_arn         = aws_kms_key.main.arn
  logs_kms_key_arn    = aws_kms_key.main.arn
  multi_az            = var.db_multi_az
  deletion_protection = var.environment != "dev"
  skip_final_snapshot = var.environment == "dev"
  apply_immediately   = var.environment == "dev"
}

module "app" {
  source = "../../modules/ecs_service"

  name           = local.name
  vpc_id         = module.network.vpc_id
  app_subnet_ids = module.network.app_subnet_ids
  repository_url = module.ecr.repository_url
  repository_arn = module.ecr.repository_arn
  image_tag      = var.image_tag
  min_tasks      = var.min_tasks
  max_tasks      = var.max_tasks

  target_group_arn        = module.alb.target_group_arn
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alb_arn_suffix          = module.alb.alb_arn_suffix

  db_host       = module.database.address
  db_port       = module.database.port
  db_name       = module.database.db_name
  db_secret_arn = module.database.master_secret_arn

  kms_key_arn      = aws_kms_key.main.arn
  logs_kms_key_arn = aws_kms_key.main.arn
  listener_arn     = module.alb.listener_arn

  permissions_boundary_arn = local.permissions_boundary_arn
}

module "observability" {
  source = "../../modules/observability"

  name                    = local.name
  kms_key_arn             = aws_kms_key.main.arn
  alert_email             = var.alert_email == "" ? null : var.alert_email
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  cluster_name            = module.app.cluster_name
  service_name            = module.app.service_name
  db_identifier           = module.database.identifier
  monthly_budget_usd      = var.monthly_budget_usd
  project_tag             = var.project
}
