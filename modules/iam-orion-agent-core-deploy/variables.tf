variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno AWS."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser 'dev', 'staging' o 'prod'."
  }
}

variable "github_repository" {
  description = "Repositorio GitHub que puede asumir este role OIDC (formato owner/repo)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repository))
    error_message = "github_repository debe tener formato owner/repo."
  }
}

variable "oidc_provider_arn" {
  description = "ARN del IAM OIDC provider creado por modules/oidc-github. Tipicamente module.oidc_github.oidc_provider_arn."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN del ECR repository al cual el role tiene permiso de Pull (GetDownloadUrlForLayer, BatchGetImage, BatchCheckLayerAvailability)."
  type        = string
}

variable "agentcore_runtime_role_arns" {
  description = "Lista opcional de ARNs de Bedrock AgentCore Runtime roles que el role puede pasar via sts:AssumeRole al desplegar un agent."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
