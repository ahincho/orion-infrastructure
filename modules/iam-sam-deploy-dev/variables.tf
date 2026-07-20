variable "project_name" {
  description = "Project name (kebab-case). Used in role/policy naming and tag values."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be kebab-case, start with a letter, end with alphanumeric."
  }
}

variable "environment" {
  description = "Deployment environment. Phase 1 is `dev` only."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "staging"], var.environment)
    error_message = "environment must be one of: dev, prod, staging."
  }
}

variable "aws_region" {
  description = "AWS region for ARNs in policy resources."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID where the role will be created."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository (e.g. ahincho)."
  type        = string
  default     = "ahincho"
}

variable "github_repo" {
  description = "GitHub repository that can assume this role (e.g. orion-backend)."
  type        = string
}

variable "github_branch" {
  description = "Branch ref that can assume this role (e.g. refs/heads/main)."
  type        = string
  default     = "refs/heads/main"
}

variable "github_environments" {
  description = "GH Environment names (or * for any) that can assume this role."
  type        = list(string)
  default     = ["dev"]
}

variable "s3_artifacts_bucket" {
  description = "S3 bucket used by SAM CLI for deployment artifacts (e.g. orion-sam-artifacts-dev)."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources (merged with common_tags)."
  type        = map(string)
  default     = {}
}
