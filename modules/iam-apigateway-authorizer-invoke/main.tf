###############################################################################
# Module: iam-apigateway-authorizer-invoke
# -----------------------------------------------------------------------------
# Crea el IAM role que API Gateway ASSUME para invocar el Lambda authorizer
# (REQUEST type) en orion-backend. Distinto del execution role del propio
# Lambda (lambda.amazonaws.com); este role es asumido por API Gateway
# (apigateway.amazonaws.com) para que el servicio pueda hacer
# lambda:InvokeFunction sobre el authorizer function.
#
# Decisiones de diseno:
#   - Trust policy: solo apigateway.amazonaws.com (sin condiciones para dev;
#     prod deberia aniadir aws:SourceAccount = <this-account> y opcionalmente
#     aws:SourceArn = arn:aws:execute-api:...:<api-id>/*/* para restringir
#     cual API puede invocar el authorizer).
#   - Inline policy: lambda:InvokeFunction con scope explicito al ARN del
#     authorizer function. NO se otorga lambda:InvokeFunction sobre todos
#     los functions (least privilege).
#   - Sin managed policies (no aplica ninguna de las oficiales).
#   - Sin VPC ni SG (no es necesario; API Gateway invoca por IAM, no por red).
#   - Naming: <project>-<env>-authorizer-invoke-<random> via
#     name_prefix (igual patron que iam-lambda-exec). El prefijo se
#     acorta a "authorizer-invoke" (sin "apigateway-") porque AWS IAM
#     limita name_prefix a 38 chars (64 - 26 del sufijo aleatorio).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "iam-apigateway-authorizer-invoke"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )
}

###############################################################################
# IAM Role
###############################################################################
# checkov:skip=CKV_AWS_61:Trust limited to service principal apigateway.amazonaws.com.
# checkov:skip=CKV_AWS_60:Trust limited to Service principal apigateway (no AWS account access).
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  # name_prefix <= 38 chars (AWS IAM limit: 64 - 26 suffix). El nombre
  # completo se forma como `<project>-<env>-authorizer-invoke-<random>`.
  # Nota: usamos "authorizer-invoke" (no "apigateway-authorizer-invoke")
  # para mantener el prefijo < 38 chars. El "apigateway" service es
  # implicito en el trust policy.
  name_prefix          = "${var.project_name}-${var.environment}-authorizer-invoke-"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-authorizer-invoke"
  })
}

###############################################################################
# Inline policy: lambda:InvokeFunction scoped to the authorizer function ARN
###############################################################################
# checkov:skip=CKV_AWS_107:Action especifica (lambda:InvokeFunction); resource scope-restricted a un unico function ARN.
# checkov:skip=CKV_AWS_108:Sin acceso a S3; solo lambda invoke.
# checkov:skip=CKV_AWS_109:Role NO gestiona otros recursos; permission management no aplica.
# checkov:skip=CKV_AWS_110:Role NO escala privilegios (no iam:PassRole, no sts:AssumeRole chain).
# checkov:skip=CKV_AWS_111:Action especifica sobre ARN explicito.
# checkov:skip=CKV_AWS_356:Una unica action, scope a ARN unico.
# checkov:skip=CKV_AWS_290:Sin acciones cross-service.
data "aws_iam_policy_document" "invoke_authorizer" {
  statement {
    sid    = "LambdaInvokeAuthorizer"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [var.authorizer_function_arn]
  }
}

resource "aws_iam_role_policy" "inline" {
  name   = "${var.project_name}-${var.environment}-authorizer-invoke-inline"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.invoke_authorizer.json
}
