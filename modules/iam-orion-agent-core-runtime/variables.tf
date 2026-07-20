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

# Trust policy tightening. Si se provee el ARN del AgentRuntime, la trust policy
# exige que el assume provenga especificamente de ese runtime (anti-confused-
# deputy estricto). Si se deja vacio (default antes de que el runtime exista),
# la trust queda solo con el service principal bedrock-agentcore.amazonaws.com
# (loose: cualquier runtime de la cuenta podria assumir). Esto permite crear
# primero el role, luego el runtime, y finalmente reapuntar el role al ARN
# concreto en una sola variable.
variable "runtime_arn" {
  description = "ARN del AgentRuntime que puede assumir este role (formato arn:aws:bedrock-agentcore:<region>:<account>:runtime/<id>). Vacio inicialmente; se actualiza tras la creacion del AgentRuntime en live/dev/main.tf para tightens la trust policy."
  type        = string
  default     = ""

  validation {
    condition     = var.runtime_arn == "" || can(regex("^arn:aws:bedrock-agentcore:[a-z0-9-]+:[0-9]+:runtime/.+", var.runtime_arn))
    error_message = "runtime_arn debe estar vacio o tener formato arn:aws:bedrock-agentcore:<region>:<account>:runtime/<id>."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
