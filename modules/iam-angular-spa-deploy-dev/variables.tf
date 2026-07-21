variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en el nombre del IAM role."
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

variable "aws_region" {
  description = "Region AWS donde se deployan los recursos (para construir ARN templates)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region debe tener formato like 'us-east-1'."
  }
}

variable "oidc_provider_arn" {
  description = "ARN del IAM OIDC provider creado por modules/oidc-github. Tipicamente module.oidc_github.oidc_provider_arn."
  type        = string
}

variable "github_repository" {
  description = "Repositorio GitHub que puede asumir este role OIDC (formato owner/repo). Para Angular SPA ORION debe ser 'ahincho/orion-frontend'."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repository))
    error_message = "github_repository debe tener formato owner/repo."
  }
}

variable "bucket_name" {
  description = "Nombre del bucket S3 del SPA (e.g. 'orion-frontend-dev'). Usado para construir los ARN patterns del S3ManageObjects statement."
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "ID del CloudFront distribution (e.g. 'E1ABC2DEF3GHIJ'). Usado para construir el ARN del create-invalidation statement."
  type        = string
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
