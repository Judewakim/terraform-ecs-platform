variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  description = "Isolated subnets with no internet route."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for storage and the managed password secret."
  type        = string
}

variable "engine_major_version" {
  type    = string
  default = "17"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "shortlink"
}

variable "username" {
  type    = string
  default = "app"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Standby replica in a second AZ. Doubles cost; on for prod."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "apply_immediately" {
  type    = bool
  default = false
}

variable "logs_kms_key_arn" {
  description = "KMS key for the RDS log groups."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
