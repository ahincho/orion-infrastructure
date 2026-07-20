###############################################################################
# Module: ssm-bootstrap
# -----------------------------------------------------------------------------
# Crea los SSM Parameters cross-ORION que orion-backend consume via
# `{{resolve:ssm:/orion/...}}` en su template.yaml.
#
# Parametros (SecureString + AWS-managed CMK):
#   /orion/secret/jwt-arn          ARN del JWT signing secret
#   /orion/db/secret-arn           ARN del RDS master secret
#   /orion/eventbridge/bus-arn     ARN del bus EventBridge
#   /orion/cors/allowed-origins    JSON list de origins CORS
#
# Decisiones de diseno:
#   - Inputs opcionales + `for_each` (no count) sobre un map filtrado.
#     Asi el modulo se puede validar/aplicar standalone con defaults
#     sensatos; el orquestador pasa los ARNs reales para habilitarlos.
#     `for_each` permite que los values sean `known after apply` (ARNs
#     de recursos AWS no se conocen hasta apply); las keys son estaticas
#     y conocidas en plan time.
#   - Todos los params son de tipo `SecureString` con `key_id=alias/aws/ssm`
#     (AWS-managed CMK, sin coste). KMS encryption forzada para cumplir
#     checkov CKV_AWS_337 + CKV2_AWS_34 sin skip.
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

  # Map de SSM params opcionales (ARN-resolvers). Keys estaticas conocidas
  # en plan time. Values pueden ser unknown (known after apply) — Terraform
  # 1.5+ soporta for_each con valores unknown siempre que las KEYS sean
  # estaticas (lo cual es nuestro caso). NO hacemos filtering con `if v != ""`
  # porque eso haria depend de unknown values y rompe plan.
  #
  # Convencion para callers: pasar var.* = "" es OK; el SSM param se crea
  # con value="" (no falla, solo no tiene valor util).
  optional_arn_params = {
    "/orion/secret/jwt-arn"      = var.jwt_secret_arn
    "/orion/db/secret-arn"       = var.db_secret_arn
    "/orion/eventbridge/bus-arn" = var.eventbridge_bus_arn
  }
}

###############################################################################
# ARN-resolver SSM params (for_each en lugar de count para tolerar values
# known-after-apply). Cada entry es una SecureString con AWS-managed CMK.
###############################################################################
resource "aws_ssm_parameter" "optional_arn" {
  for_each = local.optional_arn_params

  name        = each.key
  description = "ARN resolver SSM param: ${each.key}"
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = each.value

  tags = local.common_tags
}

###############################################################################
# CORS allowed origins whitelist (always-on, lista JSON-encoded).
###############################################################################
resource "aws_ssm_parameter" "cors_allowed_origins" {
  name        = "/orion/cors/allowed-origins"
  description = "CORS allowed origins whitelist (JSON array). Consumed by orion-backend HTTP API middleware with 5min cache."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = local.cors_origins_json

  tags = local.common_tags
}
