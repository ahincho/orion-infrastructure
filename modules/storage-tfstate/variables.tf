variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en el nombre del bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars)."
  }
}

variable "environment" {
  description = "Nombre del entorno (dev, staging, prod). Sufijo del bucket."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "lifecycle_transition_to_ia_days" {
  description = "Dias antes de transicionar objetos a Infrequent Access. 0 = deshabilitado."
  type        = number
  default     = 0
}

variable "lifecycle_transition_to_glacier_days" {
  description = "Dias antes de transicionar objetos a Glacier. 0 = deshabilitado."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags adicionales aplicados al bucket S3 y sus recursos hijos."
  type        = map(string)
  default     = {}
}
