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

variable "vpc_cidr" {
  description = "CIDR IPv4 del VPC principal. Default 10.20.0.0/16 (~65k IPs)."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR IPv4 valido."
  }
}

variable "azs" {
  description = "Lista explicita de Availability Zones (e.g. ['us-east-1a','us-east-1b']). Vacia = primeras N disponibles, donde N = length(public_subnet_cidrs)."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets publicas (1 por AZ, en orden)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas (1 por AZ, mismo orden y length que public_subnet_cidrs)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "single_nat_gateway" {
  description = "true = 1 NAT Gateway compartido entre AZs (dev only). false = 1 NAT por AZ. Para dev se recomienda true para ahorrar ~$32/mes/AZ extra."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "true = crea S3 gateway endpoint y los interface endpoints listados en vpc_endpoint_services."
  type        = bool
  default     = true
}

variable "vpc_endpoint_services" {
  description = "Servicios AWS para los que crear Interface VPC endpoints (cuando enable_vpc_endpoints=true). Costo ~$0.01/h/AZ/servicio."
  type        = set(string)
  default = [
    "secretsmanager",
    "logs",
    "ssm",
    "events",
    "ecr.api",
    "ecr.dkr",
  ]
}

variable "flow_log_retention_days" {
  description = "Retencion CW Logs para VPC flow logs. Dev = 7-30d."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days debe ser un valor de retencion valido."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
