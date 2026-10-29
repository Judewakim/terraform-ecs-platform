variable "name" {
  description = "Name prefix (32 characters max for the load balancer name)."
  type        = string

  validation {
    condition     = length(var.name) <= 28
    error_message = "name must be 28 characters or fewer so target group names fit."
  }
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "target_port" {
  description = "Port the containers listen on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path the load balancer polls to decide if a task can take traffic."
  type        = string
  default     = "/ready"
}

variable "certificate_arn" {
  description = "ACM certificate ARN. Set it to serve HTTPS and redirect HTTP; leave null for HTTP only."
  type        = string
  default     = null
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "access_logs_enabled" {
  type    = bool
  default = true
}

variable "access_log_retention_days" {
  type    = number
  default = 30
}

variable "force_destroy_logs" {
  description = "Let terraform destroy delete the log bucket with logs in it. Fine for dev."
  type        = bool
  default     = false
}
