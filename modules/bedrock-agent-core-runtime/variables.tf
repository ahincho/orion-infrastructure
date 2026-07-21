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

# Nombre logico del AgentRuntime dentro de Bedrock AgentCore.
# Restricciones de AWS API: ^[a-zA-Z][a-zA-Z0-9_]{0,47}$ (sin guiones).
# Por lo tanto pasamos snake_case aqui aunque el resto del repo usa kebab-case
# para paths/roles/etc.
variable "agent_runtime_name" {
  description = "Nombre del AgentRuntime (formato Bedrock AgentCore: ^[a-zA-Z][a-zA-Z0-9_]{0,47}$, NO admite guiones)."
  type        = string
  default     = "orion_agent_core_dev"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.agent_runtime_name))
    error_message = "agent_runtime_name debe empezar con letra y contener solo letras/digitos/underscores (max 48 chars)."
  }
}

# Container image URI en ECR. Formato: <registry>/<repo>:<tag>.
# Importante: hasta que el workflow de deploy (futuro PR #46) publique la
# primera imagen con tag concreto, el plan avisara de "implicit dependency".
variable "container_uri" {
  description = "URI completa del container image en ECR (incluyendo tag). Ej: '<account>.dkr.ecr.us-east-1.amazonaws.com/orion-agent-core-dev:latest'."
  type        = string
}

# ARN del IAM Role asumido por el contenedor dentro del AgentCore Runtime.
# Típicamente module.iam_orion_agent_core_runtime.runtime_role_arn.
variable "role_arn" {
  description = "ARN del IAM Role execution que el contenedor asume al arrancar."
  type        = string
}

# Network mode: PUBLIC (default, free) o VPC (requiere +security_groups +subnets).
variable "network_mode" {
  description = "Network mode del Runtime. PUBLIC por defecto (sin VPC connector). Para VPC mode se requieren security_groups y subnets."
  type        = string
  default     = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "VPC"], var.network_mode)
    error_message = "network_mode debe ser 'PUBLIC' o 'VPC'."
  }
}

variable "subnets" {
  description = "Lista de subnet IDs (solo si network_mode='VPC'). El provider requiere minimo 1."
  type        = list(string)
  default     = []
}

variable "security_groups" {
  description = "Lista de security group IDs (solo si network_mode='VPC'). El provider requiere minimo 1."
  type        = list(string)
  default     = []
}

# Variables de entorno que se pasan al contenedor al arrancar.
# El agente las consume via Pydantic Settings (env_prefix='ORION_AGENT_');
# AWS_REGION queda exenta por convencion del AWS SDK.
variable "environment_variables" {
  description = "Map de variables de entorno pasadas al contenedor. Típicos: AWS_REGION (exenta por SDK AWS), ORION_AGENT_* (consumidas por Pydantic Settings)."
  type        = map(string)
  default     = {}
}

variable "description" {
  description = "Descripcion libre del AgentRuntime (max 4096 chars)."
  type        = string
  default     = "OrionAgentCore dev runtime (Bedrock AgentCore)."
}

# Nombre del endpoint (alias).
# Mismas restricciones que agent_runtime_name.
variable "endpoint_name" {
  description = "Nombre del endpoint (alias) creado sobre el AgentRuntime. ^[a-zA-Z][a-zA-Z0-9_]{0,47}$."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.endpoint_name))
    error_message = "endpoint_name debe empezar con letra y contener solo letras/digitos/underscores (max 48 chars)."
  }
}

variable "endpoint_description" {
  description = "Descripcion libre del endpoint (max 256 chars)."
  type        = string
  default     = "Default dev endpoint for OrionAgentCore."
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
