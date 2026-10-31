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

variable "github_owner_id" {
  description = "Numeric GitHub user/org ID. Find it: gh api users/<owner> --jq .id"
  type        = string
  default     = "59939123"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID. Find it: gh api repos/<owner>/<repo> --jq .id"
  type        = string
  default     = "1438557498"
}

variable "create_github_oidc_provider" {
  description = "An account can hold only one GitHub OIDC provider. Set false if another repo already created it."
  type        = bool
  default     = true
}
