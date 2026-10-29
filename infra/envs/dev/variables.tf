variable "project" {
  type    = string
  default = "shortlink"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  description = "One shared NAT (cheap) vs one per AZ (survives an AZ outage)."
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Container image tag to deploy. CI passes the commit SHA."
  type        = string
}

variable "min_tasks" {
  type    = number
  default = 2
}

variable "max_tasks" {
  type    = number
  default = 4
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "certificate_arn" {
  description = "Optional ACM certificate for HTTPS."
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Email for alarms and budget alerts."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  type    = number
  default = 25
}
