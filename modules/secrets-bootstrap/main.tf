###############################################################################
# Module: secrets-bootstrap
# -----------------------------------------------------------------------------
# Crea el secret en AWS Secrets Manager para el JWT HS256 signing key que
# usara orion-backend (contexts/identity + contexts/authorizer).
#
# Decisiones de diseno:
#   - El secreto se genera del lado de TF con `random_password` (length=64,
#     special=false para evitar chars problematicos en JWT libs). El valor
#     vive en el state de TF; esto es OK para un secreto de aplicacion
#     regenerable (rotacion manual o re-apply si el state se pierde).
#   - El valor no se loguea ni se imprime (random_password solo expone .result).
#   - Estructura del secret: JSON con `algorithm`, `kty`, `key` (raw base64-like
#     string). Compatible con la libreria `jose` que usa orion-backend.
#   - KMS encryption con AWS-managed CMK (sin `kms_key_id`). Para prod se
#     subministrara un KMS CMK explicito via un futuro modules/kms/.
#   - Recovery window configurable: 0 para dev (delete sin espera), 7+ para
#     staging/prod (rollback).
#   - Solo se rota manualmente (no `aws_secretsmanager_secret_rotation`):
#     rotar un JWT signing key requiere invalidar todos los tokens emitidos
#     y re-firmarlos con el nuevo key. Es una operacion masiva que se hara
#     via un Lambda custom (futuro modules/secrets-rotation/).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module     = "secrets-bootstrap"
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "ahincho/orion-infrastructure"
    }
  )
}

###############################################################################
# random_password: HS256 signing key
###############################################################################
# special=false para evitar caracteres que rompen parsers JSON/JWT: /, ", \.
# upper+lower+numeric=True para entropia completa (~5.95 bits/char).
# 64 chars ~= 380 bits de entropia (suficiente para HS256).
resource "random_password" "jwt_signing" {
  length  = var.jwt_secret_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

###############################################################################
# aws_secretsmanager_secret: el secret en si
###############################################################################
resource "aws_secretsmanager_secret" "jwt_signing" {
  # checkov:skip=CKV_AWS_149:rotacion del JWT signing key requiere un Lambda custom (createSecret/setSecret/testSecret/finishSecret) + invalidacion masiva de tokens. Se difiere al futuro modules/secrets-rotation/.
  # checkov:skip=CKV_AWS_173:dev env usa AWS-managed CMK de Secrets Manager (encryption at rest por defecto). KMS CMK explicito se difiere al futuro modules/kms/ para prod.
  # checkov:skip=CKV2_AWS_57:Secrets bootstrap no requiere resource-based policy; el acceso es via IAM (caller asume role con secretsmanager:GetSecretValue).
  name                    = "${var.project_name}-${var.environment}-${var.jwt_secret_name_suffix}"
  description             = "JWT HS256 signing key for orion-backend ${var.environment} (length=${var.jwt_secret_length}, regenerated on tf apply if resource recreated)."
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.jwt_secret_name_suffix}"
  })
}

###############################################################################
# aws_secretsmanager_secret_version: valor inicial (con JSON estructurado)
###############################################################################
# JSON shape esperado por los handlers Lambda (jose import):
#   {
#     "version": 1,
#     "alg": "HS256",
#     "kty": "oct",
#     "use": "sig",
#     "key": "<random-password>",
#     "rotatedAt": "<iso8601>"
#   }
resource "aws_secretsmanager_secret_version" "jwt_signing_initial" {
  secret_id = aws_secretsmanager_secret.jwt_signing.id
  secret_string = jsonencode({
    version   = 1
    alg       = "HS256"
    kty       = "oct"
    use       = "sig"
    key       = random_password.jwt_signing.result
    rotatedAt = timestamp()
  })

  lifecycle {
    # Evita que un destroy del secret version borre el secret real
    # inadvertidamente. Solo borra la version inicial.
    ignore_changes = [secret_string]
  }
}
