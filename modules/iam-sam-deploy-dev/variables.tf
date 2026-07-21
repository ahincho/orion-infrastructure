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

variable "aws_region" {
  description = "Region AWS donde se deployan los recursos (para construir ARN templates)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region debe tener formato like 'us-east-1'."
  }
}

variable "oidc_provider_arn" {
  description = "ARN del IAM OIDC provider creado por modules/oidc-github. Tipicamente module.oidc_github.oidc_provider_arn."
  type        = string
}

variable "github_repository" {
  description = "Repositorio GitHub que puede asumir este role OIDC (formato owner/repo)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repository))
    error_message = "github_repository debe tener formato owner/repo."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "additional_iam_role_arns" {
  description = <<-EOT
    Lista adicional de ARNs de IAM roles que sam deploy puede pasar a
    CloudFormation (iam:PassRole). Se concatena con los 3 ARNs patron
    (orion-backend-dev*, orion-*-exec-dev, orion-lambda-runtime-dev*).

    Usar para roles cross-cutting como el de API Gateway authorizer
    invoke (module.iam_apigateway_authorizer_invoke.role_arn), que
    API Gateway ASSUME para invocar el Lambda authorizer y que sam
    deploy debe poder PassRole al crear el AWS::ApiGatewayV2::Authorizer
    con AuthorizerCredentialsArn.
  EOT
  type        = list(string)
  default     = []
}
