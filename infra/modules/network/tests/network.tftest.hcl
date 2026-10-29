# Offline: mocked provider, no AWS credentials, no cost. Run: terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock" }
  }
}

variables {
  name             = "test"
  logs_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock"
}

run "single_nat_by_default" {
  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Default should create one shared NAT gateway."
  }
}

run "nat_per_az_when_requested" {
  variables {
    single_nat_gateway = false
    az_count           = 3
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "single_nat_gateway = false should create one NAT per AZ."
  }
}

run "tiers_do_not_overlap" {
  assert {
    condition = length(distinct(concat(
      aws_subnet.public[*].cidr_block,
      aws_subnet.app[*].cidr_block,
      aws_subnet.db[*].cidr_block,
    ))) == 6
    error_message = "Every subnet CIDR must be unique."
  }
}

run "database_tier_has_no_internet_route" {
  # Mocks reuse IDs across a resource type, so give each route table its own.
  override_resource {
    target = aws_route_table.db
    values = { id = "rtb-db" }
  }
  override_resource {
    target = aws_route_table.public
    values = { id = "rtb-public" }
  }
  override_resource {
    target = aws_route_table.app
    values = { id = "rtb-app" }
  }

  assert {
    condition = alltrue(concat(
      [aws_route.public_internet.route_table_id != aws_route_table.db.id],
      [for r in aws_route.app_nat : r.route_table_id != aws_route_table.db.id],
    )) && length(aws_route_table.db.route) == 0
    error_message = "The database route table must have no route to the internet or a NAT."
  }
}

run "no_public_ips_by_default" {
  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }
}

run "rejects_non_16_cidr" {
  command = plan
  variables {
    cidr_block = "10.0.0.0/24"
  }
  expect_failures = [var.cidr_block]
}
