variable "name" {
  type = string
}

variable "kms_key_arn" {
  description = "Key for the SNS topic. Its policy must let CloudWatch use it."
  type        = string
}

variable "alert_email" {
  description = "Where alarms and budget alerts go. null = no email subscription and no budget."
  type        = string
  default     = null
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "error_threshold_per_minute" {
  description = "App 5xx responses per minute that count as an incident."
  type        = number
  default     = 5
}

variable "latency_p95_seconds" {
  type    = number
  default = 1
}

variable "monthly_budget_usd" {
  type    = number
  default = 25
}

variable "project_tag" {
  description = "Value of the Project tag the budget filters on. Activate it as a cost allocation tag in Billing first."
  type        = string
}
