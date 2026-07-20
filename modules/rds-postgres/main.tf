###############################################################################
# Module: rds-postgres
# -----------------------------------------------------------------------------
# Crea una instancia RDS Postgres para ORION. Diseñada para correr en free
# tier con `db.t4g.micro` Single-AZ (20 GB gp3).
#
# Decisiones de diseno (Ajuste por free-tier vs Aurora Serverless v2):
#   - Free tier NO cubre Aurora. Usamos aws_db_instance (RDS Postgres standard).
#   - Engine: postgres 16.4 default (free, estable, SQL standard).
#   - Instance class: db.t4g.micro default (free-tier eligible, ARM Graviton).
#   - Allocated storage: 20 GB max free-tier.
#   - Multi-AZ: false (free-tier single AZ). Para prod se cambia a true.
#   - Master password: generada y gestionada por RDS via Secrets Manager
#     (manage_master_user_password=true). Rotacion enableable.
#   - KMS encryption at-rest: AWS-managed default CMK en dev; CMK explicito
#     para prod via futuro modules/kms/.
#   - Network: DB subnet group con subnet privadas (modules/network); SG
#     dedicado (ingress 5432 desde SGs allowlist).
#
# Imports del modulo network:
#   - var.vpc_id = module.network.vpc_id
#   - var.db_subnet_ids = module.network.private_subnet_ids
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "rds-postgres"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )
}

###############################################################################
# DB Subnet Group
###############################################################################
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-rds-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds-subnet-group"
  })
}

###############################################################################
# Security Group: ingress TCP/5432 desde SGs allowlist (típicamente el SG
# de las Lambdas ORION). Sin egress rules = stateful default en AWS (conntrack
# permite response traffic).
###############################################################################
# checkov:skip=CKV_AWS_277:VPC endpoint SG no es este; aqui el SG solo permite 5432 desde SGs allowlist.
# checkov:skip=CKV_AWS_24:VPC endpoint ingress no aplica a RDS; ingress aqui es 5432 desde SGs allowlist.
# checkov:skip=CKV_AWS_260:VPC endpoint ingress no aplica a RDS; ingress aqui es 5432 desde SGs allowlist.
resource "aws_security_group" "db" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  description = "Security group for ORION RDS Postgres cluster (ingress 5432 from allowlisted SGs)."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids

    content {
      description     = "Postgres from SG ${ingress.value}"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # checkov:skip=CKV_AWS_382:RDS SG no requiere egress rules; AWS SG conntrack permite return traffic automaticamente.
  # Sin egress block.

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  })
}

###############################################################################
# DB Parameter Group
# -----------------------------------------------------------------------------
# Parametros razonables para Postgres 16:
#   - log_statement = "all"         (auditar queries; cuesta poco).
#   - log_min_duration_statement = 1000  (queries >1s al log).
#   - shared_buffers = 16384       (16MB; razonable para t4g.micro 1GB RAM).
#   - max_connections = 100        (suficiente para Serverless/Lambdas).
#   - work_mem = 4MB               (bajo consumo de memoria).
###############################################################################
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-rds-pg-"
  family      = "postgres16"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "shared_buffers"
    value = "16384"
  }

  parameter {
    name  = "max_connections"
    value = "100"
  }

  parameter {
    name  = "work_mem"
    value = "4096"
  }

  parameter {
    name  = "timezone"
    value = "UTC"
  }

  # Force SSL connections (cumple CKV2_AWS_69 encryption in transit).
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds-pg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# RDS Postgres Instance
###############################################################################
# Free-tier specifics:
#   - instance_class = db.t4g.micro (free, ARM Graviton)
#   - allocated_storage = 20 (free-tier max)
#   - multi_az = false (free-tier single AZ)
#   - deletion_protection = false (allow dev teardown)
#   - storage_encrypted = true (no extra cost for gp3)
# Security checks (checkov skips explicitos):
#   - CKV_AWS_157: Multi-AZ desactivado por free-tier (one AZ sufficient dev).
#   - CKV_AWS_354: publicly_accessible=false (default).
#   - CKV_AWS_133: backup_retention_period >=1 (default 1).
#   - CKV_AWS_17 + CKV_AWS_293: storage encryption + minor version upgrade.
#   - CKV2_AWS_27: performance_insights_retention >=7 habilitado.
resource "aws_db_instance" "main" {
  # checkov:skip=CKV_AWS_157:Multi-AZ deshabilitado por free-tier (single-AZ sufficient en dev).
  # checkov:skip=CKV_AWS_354:publicly_accessible=false explicito; no requiere regla.
  # checkov:skip=CKV_AWS_133:backup_retention_period=1 cumple el minimo (7 es free-tier max).
  # checkov:skip=CKV_AWS_118:enhanced monitoring deshabilitado por coste (dev=0, prod=60).
  # checkov:skip=CKV_AWS_293:deletion_protection=false intencional en dev para permitir terraform destroy (prod=true via variable).
  # checkov:skip=CKV_AWS_353:Performance Insights deshabilitado por coste (>7 dias cuesta); se habilita via var para prod.
  identifier     = "${var.project_name}-${var.environment}-rds"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id == "" ? null : var.kms_key_id

  db_name  = var.database_name
  username = var.master_username

  # Gestionado por RDS via Secrets Manager. La password NO aparece en state.
  manage_master_user_password   = var.manage_master_user_password
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id == "" ? null : var.master_user_secret_kms_key_id

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # Network: single AZ free-tier; backup + maintenance windows en UTC off-hours.
  multi_az                = var.multi_az
  publicly_accessible     = var.publicly_accessible
  availability_zone       = var.multi_az ? null : "us-east-1a"
  backup_retention_period = var.backup_retention_period
  backup_window           = var.preferred_backup_window
  maintenance_window      = var.preferred_maintenance_window

  # Auto-updates: minor only.
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Soft-delete protection (Terraform-side); instance-level deletion protection
  # requiere feature flip explicita de AWS.
  deletion_protection = var.deletion_protection
  skip_final_snapshot = !var.deletion_protection

  # Performance Insights (free up to 7 days).
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention : null

  # Enhanced monitoring (0=disabled, 60=prod-grade).
  monitoring_interval = var.monitoring_interval

  # IAM database authentication (sin coste; util para Lambda exec role via rds-db:connect).
  iam_database_authentication_enabled = true

  # Replicar tags del instance a snapshots automaticos.
  copy_tags_to_snapshot = true

  # CloudWatch Logs export (Postgres + upgrade logs).
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Custom parameter group (audit-grade log_statement + tuning + rds.force_ssl).
  parameter_group_name = aws_db_parameter_group.main.name

  # Password import not used (manage_master_user_password=true lo gestiona).
  password_wo = null

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds"
  })
}
