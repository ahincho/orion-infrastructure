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

variable "bus_name" {
  description = "Nombre completo del bus. Default: $${project_name}-events-$${environment} (= orion-events-dev)."
  type        = string
  default     = ""

  validation {
    condition     = var.bus_name == "" || can(regex("^[a-z0-9-]{3,50}$", var.bus_name))
    error_message = "bus_name debe ser kebab-case (3-50) o vacio (usa default)."
  }
}

variable "enable_default_log_rule" {
  description = "Si true, crea un CW Log Group + regla que captura TODOS los eventos del bus para observabilidad base."
  type        = bool
  default     = true
}

variable "event_log_retention_days" {
  description = "Retencion CW Logs del evento log group (cuando enable_default_log_rule=true). dev=7-30, prod>=90."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.event_log_retention_days)
    error_message = "event_log_retention_days debe ser un valor valido."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
