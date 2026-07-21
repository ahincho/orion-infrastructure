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

variable "api_gateway_source_arn" {
  description = <<-EOT
    ARN del API Gateway que puede assumir este role. Si se setea (no vacio),
    la trust policy anade una condicion aws:SourceArn (StringLike) que
    restringe aun mas quien puede assumir el role (ademas de la condicion
    aws:SourceAccount que siempre se aplica).

    Tipicamente: arn:aws:execute-api:<region>:<account>:<api-id>/*.
    Default: "" (no se anade la condicion aws:SourceArn; solo se aplica
    aws:SourceAccount).

    Usar para endurecer el trust tras crear el API Gateway (patron
    2-fases: ver AGENTS.md seccion 'iam-orion-agent-core-runtime').
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.api_gateway_source_arn == "" || can(regex("^arn:aws:execute-api:[a-z0-9-]+:[0-9]+:[a-z0-9]+/\\*$", var.api_gateway_source_arn))
    error_message = "api_gateway_source_arn debe ser vacio o un ARN valido tipo 'arn:aws:execute-api:<region>:<account>:<api-id>/*'."
  }
}
