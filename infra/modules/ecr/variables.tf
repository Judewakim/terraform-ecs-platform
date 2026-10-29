variable "name" {
  description = "Repository name."
  type        = string
}

variable "keep_images" {
  description = "How many images to keep before older ones expire."
  type        = number
  default     = 20
}

variable "force_delete" {
  description = "Allow destroy to delete the repo even if it holds images. Fine for dev, false for prod."
  type        = bool
  default     = false
}
