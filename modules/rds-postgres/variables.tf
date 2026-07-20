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

variable "engine_version" {
  description = "Postgres engine version. Default = 16.4 (ultimo estable en region us-east-1)."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Clase de instancia RDS. Default db.t4g.micro (free-tier eligible, ARM Graviton). Cambiar a db.t3.micro para x86."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = contains(["db.t3.micro", "db.t4g.micro", "db.t3.small", "db.t4g.small"], var.instance_class)
    error_message = "instance_class debe ser un free-tier eligible o small (ver lista)."
  }
}

variable "allocated_storage" {
  description = "Storage inicial en GB. Default 20 (limite free-tier)."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 100
    error_message = "allocated_storage debe estar entre 20 y 100 GB para free-tier (gp3)."
  }
}

variable "max_allocated_storage" {
  description = "Cap superior para autoscaling storage (gp3). 0 desactiva autoscaling."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Tipo de storage. gp3 (default, cheapest) o gp2."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3"], var.storage_type)
    error_message = "storage_type debe ser gp2 o gp3."
  }
}

variable "storage_encrypted" {
  description = "Si true, encripta storage at-rest (sin coste extra para gp3)."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS CMK para encryption at-rest. Vacio = AWS-managed default CMK. Para prod, subministrar CMK explicito (futuro modules/kms/)."
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Nombre de la DB inicial. Default 'orion'."
  type        = string
  default     = "orion"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,62}$", var.database_name))
    error_message = "database_name debe ser 2-63 chars, empieza con letra, solo [a-zA-Z0-9_]."
  }
}

variable "master_username" {
  description = "Master username. Default 'orion_admin'. La password NO se gestiona aqui; aws_db_instance con manage_master_user_password=true usa Secrets Manager."
  type        = string
  default     = "orion_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,62}$", var.master_username))
    error_message = "master_username debe seguir las reglas RDS (2-63 chars, empieza con letra)."
  }
}

variable "manage_master_user_password" {
  description = "Si true, RDS gestiona la master password via Secrets Manager (rotation enableable). Default true."
  type        = bool
  default     = true
}

variable "master_user_secret_kms_key_id" {
  description = "KMS CMK para encriptar el master user secret. Vacio = AWS-managed default."
  type        = string
  default     = ""
}

variable "multi_az" {
  description = "Si true, instancia Multi-AZ (HA). Default false para free-tier dev. Prod deberia usar true."
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Si true, expone el DB al internet. SIEMPRE false en ORION."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "ID del VPC donde colocar la DB subnet group y el security group del DB. Tpicamente modules/network/vpc_id."
  type        = string
}

variable "db_subnet_ids" {
  description = "Lista de subnet IDs PRIVADAS para el DB subnet group. 2+ subnets en AZs distintas."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Lista de SG IDs permitidos para ingress TCP/5432 al DB. Tpicamente el SG de las Lambdas (modules/iam-lambda-exec/lambda_sg_id) o del authorizer."
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Dias de retencion de backups automaticos. Free-tier permite hasta 7. dev=1-7, prod>=14."
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period debe estar entre 0 y 35 dias."
  }
}

variable "preferred_backup_window" {
  description = "Ventana diaria de backups (UTC). Default 03:00-04:00 UTC fuera de horario office."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Ventana semanal de mantenimiento (UTC). Default Sun 04:00-05:00 UTC."
  type        = string
  default     = "Sun:04:00-Sun:05:00"
}

variable "auto_minor_version_upgrade" {
  description = "Si true, AWS actualiza automaticamente a minor versions mas nuevas."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Si true, RDS bloquea el delete del instance. Para dev=false (allow teardown). Prod=true."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Performance Insights. dev=false (7 dias gratis; >=7 dias cuesta)."
  type        = bool
  default     = false
}

variable "performance_insights_retention" {
  description = "Retention de PI en dias. Default 7 (free). Si >7 dias, hay coste extra (~>$0.01/mes por instance)."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention)
    error_message = "performance_insights_retention debe ser 7 (free) o 731 (long-term, con coste)."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval (segundos). 0 = deshabilitado. dev=0, prod=60."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}
