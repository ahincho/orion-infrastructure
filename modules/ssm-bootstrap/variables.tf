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

# ---------------------------------------------------------------------------
# Optional inputs (ARNs cross-module). Empty default permite que el modulo
# se aplique en modo 'standalone' sin depender del orquestador. Cuando el
# orquestador los provee, los SSM params correspondientes se crean.
# ---------------------------------------------------------------------------

variable "jwt_secret_arn" {
  description = "ARN del JWT signing secret (modules/secrets-bootstrap). Vacio = no crear el SSM param /orion/secret/jwt-arn."
  type        = string
  default     = ""
}

variable "db_secret_arn" {
  description = "ARN del RDS master secret (modules/rds-postgres via manage_master_user_password). Vacio = no crear /orion/db/secret-arn."
  type        = string
  default     = ""
}

variable "eventbridge_bus_arn" {
  description = "ARN del bus EventBridge (modules/eventbridge-bus). Vacio = no crear /orion/eventbridge/bus-arn."
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "Lista de origins para CORS whitelist. Default = localhost:3000. orion-backend lo lee desde SSM via cache 5min."
  type        = list(string)
  default     = ["http://localhost:3000"]

  validation {
    condition     = length(var.cors_allowed_origins) >= 1
    error_message = "cors_allowed_origins debe tener al menos 1 origin."
  }
}

variable "lambda_subnet_ids" {
  description = "Lista de IDs de subnet privadas donde corren las Lambdas (de modules/network.private_subnet_ids). Se publica como /orion/lambda/vpc-subnet-ids comma-separated."
  type        = list(string)
  default     = []
}

variable "lambda_security_group_id" {
  description = "ID del SG de las Lambdas (modules/iam-lambda-exec.lambda_security_group_id). Se publica como /orion/lambda/security-group-id."
  type        = string
  default     = ""
}

variable "lambda_role_arn" {
  description = "ARN del IAM execution role (modules/iam-lambda-exec.role_arn). Se publica como /orion/lambda/role-arn. Opcional — los nested stacks de orion-backend pueden usar su propio role."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
