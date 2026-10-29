resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres. Ingress only from the app tier (wired in the environment root)."
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg${var.engine_major_version}-"
  family      = "postgres${var.engine_major_version}"

  # Reject any client connection that isn't TLS.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500 ms
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_293:Deletion protection is a variable; true by default, false only in dev
  #checkov:skip=CKV_AWS_157:Multi-AZ is a variable; doubles cost, off in dev
  #checkov:skip=CKV_AWS_353:Performance Insights skipped on the micro dev instance; enable for prod
  #checkov:skip=CKV_AWS_118:Enhanced monitoring adds a role and cost; CloudWatch basic metrics and alarms cover dev
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_major_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username

  # RDS creates and rotates the password in Secrets Manager. It never appears
  # in Terraform state or in this repo.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "07:00-08:00" # UTC, overnight US Eastern
  maintenance_window      = "sun:08:30-sun:09:30"
  copy_tags_to_snapshot   = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  apply_immediately = var.apply_immediately
}
