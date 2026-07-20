variable "project_name" {
  description = "Project name (kebab-case). Used in role naming and tag values."
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
  description = "GitHub organization/user that owns the repository (e.g. ahincho)."
  type        = string
  default     = "ahincho"
}

variable "github_repo" {
  description = "GitHub repository that can assume this role (e.g. orion-cognitive-agent)."
  type        = string
  default     = "orion-cognitive-agent"
}

variable "github_branch" {
  description = "Branch ref that can assume this role (e.g. refs/heads/main)."
  type        = string
  default     = "refs/heads/main"
}

variable "github_environments" {
  description = "GH Environment names that can assume this role."
  type        = list(string)
  default     = ["dev"]
}

variable "ecr_repository_name" {
  description = "Name of the ECR repo where the agent image will be pushed (e.g. orion-agent). Used to scope ECR permissions."
  type        = string
  default     = "orion-agent"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID used for inline InvokeModel smoke tests by the deploy workflow."
  type        = string
  default     = "us.anthropic.claude-sonnet-4-20250514"
}

variable "tags" {
  description = "Additional tags applied to all resources (merged with common_tags)."
  type        = map(string)
  default     = {}
}
