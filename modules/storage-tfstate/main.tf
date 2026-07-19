# =============================================================================
# Module: storage-tfstate
# =============================================================================
# Crea el bucket S3 para almacenar el state de Terraform con:
#   - Versionado habilitado (obligatorio para state + lockfile)
#   - Encriptacion server-side AES256
#   - Acceso publico bloqueado (4 flags)
#
# Uso: una instancia por entorno (live/dev invoca con environment=dev,
#      live/prod invoca con environment=prod).
#
# IMPORTANTE: la primera vez por ambiente el bucket se crea FUERA de
# Terraform via scripts/bootstrap-backend.sh (chicken-and-egg: el state
# file no puede vivir dentro del bucket que el mismo Terraform esta
# creando). Las invocaciones posteriores del modulo son idempotentes
# (bucket_exists = true, no se recrea).
# =============================================================================

locals {
  bucket_name = "${var.project_name}-tfstate-${var.environment}"
  common_tags = merge(
    var.tags,
    {
      Module      = "storage-tfstate"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )
}

###############################################################################
# S3 bucket para state
###############################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

###############################################################################
# Versionado (obligatorio para state + lockfile)
###############################################################################

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

###############################################################################
# Encriptacion server-side AES256
###############################################################################
# AES256 (SSE-S3) cumple FIPS 140-2. Suficiente para nuestro caso.
# Si en algun momento se necesita SSE-KMS, ver doc/DECISIONS de spark-match
# (mismo trade-off, mismas conclusiones).
###############################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

###############################################################################
# Bloqueo de acceso publico (4 flags)
###############################################################################

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

###############################################################################
# Lifecycle policy (opcional, configurable via variables)
###############################################################################
# Usar transition_to_ia_days para reducir costo de objetos antiguos.
# NO recomendado para el state file activo (siempre se necesita acceso rapido).
# Solo util si se hace backup historico o si el bucket se usa para otros
# archivos de Terraform (no nuestro caso).
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  count = (var.lifecycle_transition_to_ia_days > 0 || var.lifecycle_transition_to_glacier_days > 0) ? 1 : 0

  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days          = var.lifecycle_transition_to_ia_days > 0 ? var.lifecycle_transition_to_ia_days : null
      storage_class            = var.lifecycle_transition_to_ia_days > 0 ? "STANDARD_IA" : null
      noncurrent_days_to_glacier = var.lifecycle_transition_to_glacier_days > 0 ? var.lifecycle_transition_to_glacier_days : null
      glacier_storage_class    = var.lifecycle_transition_to_glacier_days > 0 ? "GLACIER" : null
    }
  }
}
