variable "project_name" {
  description = "Project name (kebab-case). Used in repo naming and tag values."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be kebab-case, start with a letter, end with alphanumeric."
  }
}

variable "environment" {
  description = "Deployment environment. Only `dev` supported today (single-env rule)."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "staging"], var.environment)
    error_message = "environment must be one of: dev, prod, staging."
  }
}

variable "deploy_role_arn" {
  description = "ARN of the orion-cognitive-agent deploy IAM role (from modules/iam-orion-agent-dev). Resource-based policy grants it push/pull on this repo."
  type        = string
}

variable "max_image_count" {
  description = "Maximum number of images to retain (lifecycle policy). Older images are auto-expired."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to all resources (merged with common_tags)."
  type        = map(string)
  default     = {}
}
