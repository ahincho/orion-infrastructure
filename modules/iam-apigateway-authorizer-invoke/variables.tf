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

variable "authorizer_function_arn" {
  description = <<-EOT
    ARN del Lambda function que actua como authorizer para API Gateway
    (REQUEST type). Tipicamente orion-authorizer-<env>. El role creado
    por este modulo permite a API Gateway (apigateway.amazonaws.com)
    asumirlo y ejecutar lambda:InvokeFunction sobre este ARN especifico.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
