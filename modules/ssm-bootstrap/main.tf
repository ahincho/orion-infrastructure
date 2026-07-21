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

  # Lambda VPC config (publishes both subnets and SG to SSM so orion-backend
  # can fetch via SAM parameter-overrides-json).
  has_lambda_vpc     = length(var.lambda_subnet_ids) > 0
  lambda_subnets_csv = join(",", var.lambda_subnet_ids)
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

###############################################################################
# Lambda VPC config — SSM-published values for orion-backend SAM deploy.
# -----------------------------------------------------------------------------
# orion-backend deploy.yml fetchea estos valores via aws ssm get-parameter
# y los pasa al recipe `sam-deploy.yml` via parameter-overrides-json.
# Asi los nested stacks (authorizer, identity, census) reciben
# VpcSubnetIds + LambdaSecurityGroupId como SAM Parameters.
###############################################################################
resource "aws_ssm_parameter" "lambda_vpc_subnet_ids" {
  count = local.has_lambda_vpc ? 1 : 0

  # checkov:skip=CKV2_AWS_34:Subnet IDs son public resource identifiers (no secretos). String type OK.
  name        = "/orion/lambda/vpc-subnet-ids"
  description = "Comma-separated private subnet IDs donde se ejecutan las Lambdas ORION (de modules/network.private_subnet_ids). Pasado al SAM deploy via parameter-overrides-json."
  type        = "String"
  value       = local.lambda_subnets_csv

  tags = local.common_tags
}

resource "aws_ssm_parameter" "lambda_security_group_id" {
  count = var.lambda_security_group_id == "" ? 0 : 1

  # checkov:skip=CKV2_AWS_34:SG ID es public resource identifier (no secreto). String type OK.
  name        = "/orion/lambda/security-group-id"
  description = "ID del SG dedicado de las Lambdas ORION (modules/iam-lambda-exec.lambda_security_group_id). Usado en AWS::Serverless::Function VpcConfig.SecurityGroupIds."
  type        = "String"
  value       = var.lambda_security_group_id

  tags = local.common_tags
}

resource "aws_ssm_parameter" "lambda_role_arn" {
  count = var.lambda_role_arn == "" ? 0 : 1

  # checkov:skip=CKV2_AWS_34:Role ARN es IAM resource identifier (no secreto). String type OK.
  name        = "/orion/lambda/role-arn"
  description = "ARN del IAM execution role centralizado (modules/iam-lambda-exec). Opcional; los nested stacks de orion-backend usan roles per-context por default."
  type        = "String"
  value       = var.lambda_role_arn

  tags = local.common_tags
}

###############################################################################
# API Gateway authorizer invoke role — SSM-published ARN.
# -----------------------------------------------------------------------------
# El workflow `CD - Deploy` de orion-backend lee este param via
# `aws ssm get-parameter` y lo pasa como `ApigatewayAuthorizerInvokeRoleArn`
# al `sam deploy` (template.yaml), evitando hardcodear el ARN en el template
# y permitiendo que el role sea rotado sin PR a orion-backend.
###############################################################################
resource "aws_ssm_parameter" "apigateway_authorizer_invoke_role_arn" {
  count = var.apigateway_authorizer_invoke_role_arn == "" ? 0 : 1

  # checkov:skip=CKV2_AWS_34:Role ARN es IAM resource identifier (no secreto). String type OK.
  name        = "/orion/iam/apigateway-authorizer-invoke-role-arn"
  description = "ARN del IAM role que API Gateway ASSUME para invocar el Lambda authorizer (modules/iam-apigateway-authorizer-invoke.role_arn). orion-backend CD - Deploy lo consume como parametro ApigatewayAuthorizerInvokeRoleArn del template.yaml."
  type        = "String"
  value       = var.apigateway_authorizer_invoke_role_arn

  tags = local.common_tags
}
