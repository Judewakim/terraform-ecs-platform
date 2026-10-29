data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count zones are used, so a new AZ in the region does not change the result
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 split into /20s: public 0-1, app 4-5, db 8-9. Leaves room to grow.
  public_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i)]
  app_cidrs    = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i + 4)]
  db_cidrs     = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i + 8)]

  nat_count = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# Lock down the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

# --- Public tier: load balancer and NAT only ---------------------------------

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Nothing launched here should get a public IP automatically.
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

# --- App tier: ECS tasks, outbound through NAT ------------------------------

resource "aws_subnet" "app" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_route_table" "app" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-app-${local.azs[count.index]}" }
}

resource "aws_route" "app_nat" {
  count = var.az_count

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # Single-NAT mode sends every AZ through NAT 0 (cheaper, one AZ is a single point of failure).
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# --- Data tier: no route to the internet at all ------------------------------

resource "aws_subnet" "db" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-db-${local.azs[count.index]}", Tier = "db" }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-db-isolated" }
}

resource "aws_route_table_association" "db" {
  count          = var.az_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# Free gateway endpoint: S3 traffic (including ECR image layers) skips the NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.app[*].id
  tags              = { Name = "${var.name}-s3" }
}

data "aws_region" "current" {}

# --- VPC flow logs -----------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; 30 days in dev to control cost
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}
