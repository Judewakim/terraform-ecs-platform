mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::127311923021:root" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test-app/1" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::test-alb-logs" }
  }
}

variables {
  name              = "test"
  vpc_id            = "vpc-123"
  public_subnet_ids = ["subnet-a", "subnet-b"]
}

run "http_only_without_certificate" {
  command = plan

  assert {
    condition     = one(aws_lb_listener.http.default_action).type == "forward"
    error_message = "Without a certificate, port 80 forwards to the app."
  }
  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "No HTTPS listener without a certificate."
  }
}

run "https_redirect_with_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock"
  }

  assert {
    condition     = one(aws_lb_listener.http.default_action).type == "redirect"
    error_message = "With a certificate, port 80 must redirect to HTTPS."
  }
  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS must use the TLS 1.3 policy."
  }
}

run "drops_invalid_headers" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields
    error_message = "The ALB must drop invalid HTTP headers (request smuggling defense)."
  }
}
