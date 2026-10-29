variable "name" {
  description = "Name prefix for every resource in the network."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. Must be a /16 so it splits into the /20 tiers."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "cidr_block must be a valid /16."
  }
}

variable "az_count" {
  description = "Availability zones to spread across (2 or 3)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT for all AZs (about $33/mo cheaper per AZ, but an AZ outage cuts outbound traffic). false = one NAT per AZ."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to keep VPC flow logs."
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key that encrypts the flow log group."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to every IAM role this module creates (see infra/bootstrap)."
  type        = string
  default     = null
}
