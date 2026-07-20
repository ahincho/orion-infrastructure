###############################################################################
# Module: ssm-bootstrap
# -----------------------------------------------------------------------------
# Crea los SSM Parameters cross-ORION que orion-backend consume via
# `{{resolve:ssm:/orion/...}}` en su template.yaml.
#
# Parametros:
#   /orion/secret/jwt-arn          String   ARN del JWT signing secret
#   /orion/db/secret-arn           String   ARN del RDS master secret
#   /orion/eventbridge/bus-arn     String   ARN del bus EventBridge
#   /orion/cors/allowed-origins    String   JSON list de origins
#
# Decisiones de diseno:
#   - Inputs opcionales + count = 0 si vacio. Asi el modulo se puede
#     validar/aplicar standalone con defaults sensatos; el orquestador
#     pasa los ARNs reales para habilitarlos.
#   - Todos los params son de tipo `String` (no `SecureString`) porque
#     contienen ARNs publicos en AWS, NO secrets. KMS encryption se
#     difiere al futuro modules/kms/ para prod.
#   - CORS allowed origins se almacena como JSON-encoded list (no CSV)
#     para consumir directo desde el Lambda con JSON.parse.
#   - Tags siguen el patron de los otros modulos.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "ssm-bootstrap"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )

  cors_origins_json = jsonencode(var.cors_allowed_origins)
}

###############################################################################
# JWT secret ARN resolver
###############################################################################
# checkov:skip=CKV_AWS_173:dev env usa AWS-managed KMS para SSM SecureString (default); las ARNs no son secretos y String type es suficiente.
# checkov:skip=CKV_AWS_338:SSM params no son CloudWatch log groups (check no aplica).
# checkov:skip=CKV2_AWS_34:dev env default decryption access OK; permisos finos via IAM ResourceTags en prod.
resource "aws_ssm_parameter" "jwt_secret_arn" {
  count = var.jwt_secret_arn == "" ? 0 : 1

  name        = "/orion/secret/jwt-arn"
  description = "ARN of JWT signing secret in Secrets Manager (consumed by orion-backend contexts/identity + contexts/authorizer)."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = var.jwt_secret_arn

  tags = local.common_tags
}

###############################################################################
# RDS master secret ARN resolver
###############################################################################
resource "aws_ssm_parameter" "db_secret_arn" {
  count = var.db_secret_arn == "" ? 0 : 1

  name        = "/orion/db/secret-arn"
  description = "ARN of RDS master secret (Aurora Postgres cluster, consumed by orion-backend DB connection layer via SecretsManager:GetSecretValue)."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = var.db_secret_arn

  tags = local.common_tags
}

###############################################################################
# EventBridge bus ARN resolver
###############################################################################
resource "aws_ssm_parameter" "eventbridge_bus_arn" {
  count = var.eventbridge_bus_arn == "" ? 0 : 1

  name        = "/orion/eventbridge/bus-arn"
  description = "ARN of the ORION EventBridge bus (orion-events-dev). Consumed by orion-backend + orion-cognitive-agent to publish events."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = var.eventbridge_bus_arn

  tags = local.common_tags
}

###############################################################################
# CORS allowed origins whitelist
###############################################################################
# Single SSM parameter (not a list) — SSM no soporta listas nativamente.
# Stored as JSON-encoded array for direct consumption via JSON.parse.
# Runtime consumption: orion-backend caches with 5min TTL.
resource "aws_ssm_parameter" "cors_allowed_origins" {
  name        = "/orion/cors/allowed-origins"
  description = "CORS allowed origins whitelist (JSON array). Consumed by orion-backend HTTP API middleware with 5min cache."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = local.cors_origins_json

  tags = local.common_tags
}
