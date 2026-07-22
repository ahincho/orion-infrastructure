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

variable "aws_region" {
  description = "Region AWS donde se deployan los recursos (para construir ARN templates)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region debe tener formato like 'us-east-1'."
  }
}

variable "shared_password_secret_name_suffix" {
  description = "Sufijo del nombre del secret en Secrets Manager. Default: 'shared-dev-password'. El nombre completo sera <project_name>-<environment>-<suffix>."
  type        = string
  default     = "shared-dev-password"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,50}$", var.shared_password_secret_name_suffix))
    error_message = "shared_password_secret_name_suffix debe ser kebab-case lowercase (3-50 chars)."
  }
}

variable "shared_password_length" {
  description = "Longitud en chars del shared dev password. Default 32 ~= 190 bits de entropia (suficiente para dev). Para prod se recomienda >= 24 con caracteres especiales."
  type        = number
  default     = 32

  validation {
    condition     = var.shared_password_length >= 16 && var.shared_password_length <= 128
    error_message = "shared_password_length debe estar entre 16 y 128."
  }
}

variable "recovery_window_in_days" {
  description = "Recovery window para delete inmediato del secret. dev=0 (delete OK sin espera), staging/prod=7+ (permite rollback)."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 7, 14, 30], var.recovery_window_in_days)
    error_message = "recovery_window_in_days debe ser 0, 7, 14 o 30."
  }
}

variable "email_domain" {
  description = "Dominio de email usado para construir emails deterministas de los usuarios seed (e.g. 'advisor-001@<email_domain>'). Default 'orion.dev' para dev. Configurar via variable para staging/prod."
  type        = string
  default     = "orion.dev"

  validation {
    condition     = can(regex("^[a-z0-9.-]{3,253}$", var.email_domain))
    error_message = "email_domain debe ser formato hostname valido (lowercase, [a-z0-9.-])."
  }
}

variable "rds_app_connection_secret_arn" {
  description = "ARN del Secrets Manager secret con las credenciales de conexion al RDS (modules/rds-postgres.app_connection_secret_arn). El Lambda execution role necesita GetSecretValue sobre este ARN para conectar al DB durante el seed."
  type        = string
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}