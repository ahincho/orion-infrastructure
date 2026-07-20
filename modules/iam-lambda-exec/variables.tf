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

variable "ssm_parameter_arns" {
  description = "Lista de ARN de SSM Parameters que las Lambdas pueden leer (GetParameter). Tpicamente los 4 paths de modules/ssm-bootstrap/."
  type        = list(string)
  default     = []
}

variable "eventbridge_bus_arn" {
  description = "ARN del custom bus EventBridge al que las Lambdas pueden publicar (PutEvents). Vacio = no crear la permission."
  type        = string
  default     = ""
}

variable "secretsmanager_tag_condition" {
  description = "Si true, anyade una regla inline con condition aws:ResourceTag/Project=<var.project_name> para permitir secretsmanager:GetSecretValue sobre secrets del proyecto. Default true; cycle-avoidance: usar tag wildcard en vez de ARN explicito."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID donde se crea el SG de las Lambdas. Tpicamente modules/network/vpc_id."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR del VPC para scope el egress del SG de las Lambdas. Default 10.20.0.0/16."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR IPv4 valido."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
