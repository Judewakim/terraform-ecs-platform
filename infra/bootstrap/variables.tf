variable "project" {
  type    = string
  default = "shortlink"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_owner" {
  type    = string
  default = "Judewakim"
}

variable "github_repo" {
  type    = string
  default = "terraform-ecs-platform"
}

variable "create_github_oidc_provider" {
  description = "An account can hold only one GitHub OIDC provider. Set false if another repo already created it."
  type        = bool
  default     = true
}
