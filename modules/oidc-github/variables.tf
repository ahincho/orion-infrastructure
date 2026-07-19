variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de roles IAM."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars)."
  }
}

variable "aws_region" {
  description = "Region AWS. Usada para restringir permisos del apply role (RequestedRegion)."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "Repositorio GitHub permitido a asumir los roles OIDC (formato owner/repo)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repository))
    error_message = "github_repository debe tener formato owner/repo."
  }
}

variable "oidc_provider_thumbprints" {
  description = "Thumbprints de los certificados del OIDC provider de GitHub Actions. GitHub rota certificados; mantener ambos durante la transicion."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "a6840fac8d59c1b2737d22c4dd2d7485b69e9b8e",
  ]
}

variable "iam_role_max_session_duration" {
  description = "Duracion maxima de la sesion OIDC en segundos. Rango: 3600-43200 (1h-12h)."
  type        = number
  default     = 3600

  validation {
    condition     = var.iam_role_max_session_duration >= 3600 && var.iam_role_max_session_duration <= 43200
    error_message = "iam_role_max_session_duration debe estar entre 3600 y 43200."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados al OIDC provider y los IAM roles."
  type        = map(string)
  default     = {}
}