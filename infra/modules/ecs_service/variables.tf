variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  description = "Private subnets with a NAT route."
  type        = list(string)
}

variable "repository_url" {
  type = string
}

variable "repository_arn" {
  type = string
}

variable "image_tag" {
  description = "Image tag to run. CI sets this to the git commit SHA."
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Floor for autoscaling. 2 keeps one task per AZ."
  type        = number
  default     = 2
}

variable "max_tasks" {
  type    = number
  default = 4
}

variable "cpu_target_percent" {
  type    = number
  default = 60
}

variable "requests_per_task_target" {
  description = "Scale out when each task averages more requests per minute than this."
  type        = number
  default     = 500
}

variable "target_group_arn" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "listener_arn" {
  description = "Listener forwarding to the target group. The service waits for it."
  type        = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "kms_key_arn" {
  description = "Key that encrypts the DB secret; the execution role needs decrypt."
  type        = string
}

variable "logs_kms_key_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to every IAM role this module creates (see infra/bootstrap)."
  type        = string
  default     = null
}
