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

variable "image_tag_mutability" {
  description = "Tag mutability de las images. MUTABLE para dev/staging (permite retag); IMMUTABLE para prod."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability debe ser 'MUTABLE' o 'IMMUTABLE'."
  }
}

variable "scan_on_push" {
  description = "Habilita ECR scan_on_push (Basic scanning). Costo extra en cuentas > free-tier; default true (recomendado)."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Cantidad maxima de images retenidas por el lifecycle policy. Mas alla, las mas viejas son untagged/marked-for-delete."
  type        = number
  default     = 30

  validation {
    condition     = var.max_image_count > 0 && var.max_image_count <= 1000
    error_message = "max_image_count debe estar entre 1 y 1000."
  }
}

variable "principal_arns_with_pull" {
  description = "Lista de ARNs de IAM principals (roles/users) que pueden pull del repo (e.g. el role de deploy de orion-cognitive-agent + el Bedrock AgentCore Runtime execution role)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
