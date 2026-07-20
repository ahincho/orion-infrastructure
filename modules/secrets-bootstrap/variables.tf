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

variable "jwt_secret_name_suffix" {
  description = "Sufijo del nombre del secret en Secrets Manager. Default: 'jwt-signing-secret'."
  type        = string
  default     = "jwt-signing-secret"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,50}$", var.jwt_secret_name_suffix))
    error_message = "jwt_secret_name_suffix debe ser kebab-case lowercase (3-50 chars)."
  }
}

variable "jwt_secret_length" {
  description = "Longitud en chars del JWT signing key (HS256 requiere >= 32 bytes). Default 64 = ~256 bits de entropia."
  type        = number
  default     = 64

  validation {
    condition     = var.jwt_secret_length >= 32 && var.jwt_secret_length <= 128
    error_message = "jwt_secret_length debe estar entre 32 y 128."
  }
}

variable "recovery_window_in_days" {
  description = "Recovery window para delete inmediato. dev=0 (delete OK sin esperar), staging/prod=7+ (permite rollback)."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 7, 14, 30], var.recovery_window_in_days)
    error_message = "recovery_window_in_days debe ser 0, 7, 14 o 30."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
