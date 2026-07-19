variable "aws_region" {
  description = "Region AWS donde desplegar la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "orion"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

# Single env (dev). Si en futuro se necesita un segundo env, ver
# AGENTS.md (seccion "Agregar un segundo AWS environment").
variable "environment" {
  description = "Nombre del entorno AWS. Unico valor soportado: dev."
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "environment debe ser exactamente 'dev' (este repo solo soporta dev)."
  }
}

# Repositorio GitHub del caller, usado para trust policy OIDC.
variable "github_repository" {
  description = "Repositorio GitHub que puede asumir los roles OIDC de Terraform (formato owner/repo)."
  type        = string
  default     = "ahincho/orion-infrastructure"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repository))
    error_message = "github_repository debe tener formato owner/repo."
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "ahincho/orion-infrastructure"
  }
}