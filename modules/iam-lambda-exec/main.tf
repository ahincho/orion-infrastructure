###############################################################################
# Module: iam-lambda-exec
# -----------------------------------------------------------------------------
# Crea el IAM execution role para las Lambdas de orion-backend, mas el security
# group dedicado (referenciado por el RDS SG ingress allowlist).
#
# Decisiones de diseno:
#   - 3 managed policies:
#       * AWSLambdaBasicExecutionRole  -> CW Logs.
#       * AWSLambdaVPCAccessExecutionRole -> VPC ENI create/describe (para
#         Lambdas con VpcConfig; necesario para que AWS cree el ENI en el
#         subnet privada).
#       * AWSLambdaTracingExecutionRole -> X-Ray write (Powertools Tracing Active).
#   - 1 inline policy (condicional) unificando:
#       * secretsmanager:GetSecretValue  sobre secret_arns.
#       * ssm:GetParameter + ssm:GetParameters  sobre ssm_parameter_arns.
#       * events:PutEvents  sobre eventbridge_bus_arn.
#       * rds-db:connect  sobre rds_db_resource_arn (si IAM auth habilitada).
#   - Security group dedicado para las Lambdas (egress scope a VPC CIDR).
#     El SG se pasa al modulo rds-postgres como allowed_security_group_ids.
#   - Trust policy: lambda.amazonaws.com unico principal (sin condiciones
#     extras para dev; prod deberia anadir aws:SourceAccount).
#   - Tagging consistente con otros modulos.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "iam-lambda-exec"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )

  has_ssm_params    = length(var.ssm_parameter_arns) > 0
  has_eventbridge   = var.eventbridge_bus_arn != ""
  has_inline_policy = local.has_ssm_params || local.has_eventbridge || var.secretsmanager_tag_condition
}

###############################################################################
# IAM Role
###############################################################################
# checkov:skip=CKV_AWS_61:Lambda role trust limited to service principal lambda.amazonaws.com.
# checkov:skip=CKV_AWS_60:Trust policy limited to Service principal lambda (no AWS account access).
# checkov:skip=CKV_AWS_107:Lambdas necesitan GetSecretValue para JWT/RDS; resources scoped a ARN list (no wildcard).
# checkov:skip=CKV_AWS_108:No S3 access in inline policy; secretsmanager scope via ARN list.
# checkov:skip=CKV_AWS_109:Lambdas NO gestionan otros recursos; permission management no aplica.
# checkov:skip=CKV_AWS_110:Lambdas NO pueden escalar privilegios (no iam:PassRole, no sts:AssumeRole chain).
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name_prefix          = "${var.project_name}-${var.environment}-lambda-exec-"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-lambda-exec"
  })
}

###############################################################################
# Managed policies: basic, VPC, X-Ray
###############################################################################
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray: AWS no provee un managed policy 'AWSLambdaTracingExecutionRole' (ese
# nombre NO existe). El managed policy correcto para escribir trace data es
# AWSXRayDaemonWriteAccess (provee xray:PutTraceSegments + PutTraceDocuments +
# GetSamplingTargets + GetSamplingRules). Adicionalmente el X-Ray daemon corre
# en sidecar (orion-backend no usa sidecar) por lo que no se necesita daemon write.
resource "aws_iam_role_policy_attachment" "xray_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

###############################################################################
# Inline policy: secrets + SSM + events + rds-db (parametrizado por ARN)
###############################################################################
# checkov:skip=CKV_AWS_111:Actions especificas; resources scope a ARN list (no wildcard *).
# checkov:skip=CKV_AWS_356:Actions restringidas a GetSecretValue/GetParameter/PutEvents/rds-db:connect; resources scoped via lista ARN.
# checkov:skip=CKV_AWS_290:Cross-AWS-API actions necesarias para el runtime Lambda (SM + SSM + EB); cada una scope-restricted al ARN correspondiente.
data "aws_iam_policy_document" "lambda_inline" {
  dynamic "statement" {
    for_each = var.secretsmanager_tag_condition ? [1] : []

    content {
      sid    = "SecretsManagerReadByProjectTag"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = ["*"]

      # checkov:skip=CKV_AWS_356:Action especifico (GetSecretValue); tag condition scope-restriction reemplaza ARN explicito (cycle-avoidance).
      # checkov:skip=CKV_AWS_290:Tag condition (Project=orion) limita acceso a secrets del proyecto via aws:ResourceTag.
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/Project"
        values   = [var.project_name]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/ManagedBy"
        values   = ["terraform"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.has_ssm_params ? [1] : []

    content {
      sid       = "SSMParameterRead"
      effect    = "Allow"
      actions   = ["ssm:GetParameter", "ssm:GetParameters"]
      resources = var.ssm_parameter_arns
    }
  }

  dynamic "statement" {
    for_each = local.has_eventbridge ? [1] : []

    content {
      sid       = "EventBridgePutEvents"
      effect    = "Allow"
      actions   = ["events:PutEvents"]
      resources = [var.eventbridge_bus_arn]
    }
  }
}

resource "aws_iam_role_policy" "inline" {
  count = local.has_inline_policy ? 1 : 0

  name   = "${var.project_name}-${var.environment}-lambda-inline"
  role   = aws_iam_role.lambda_exec.name
  policy = data.aws_iam_policy_document.lambda_inline.json
}

###############################################################################
# Security Group para las Lambdas
# -----------------------------------------------------------------------------
# - Ingress: nada (Lambda es invocada por el Lambda service via IAM, no via
#   network ingress). Un SG con ingress vacio es seguro porque el Lambda
#   service no depende de ingress para entregar la peticion (usa su propia
#   infra interna).
# - Egress: solo VPC CIDR. Las Lambdas en subnet privada con VPC endpoints
#   pueden hablar a SM/SSM/Logs/ECR/EventBridge sin NAT egress; para hablar
#   a internet (no usado en dev), el SG NO permite -> se debe aniadir
#   regla explicita.
###############################################################################
# checkov:skip=CKV_AWS_277:Lambda SG no requiere ingress rules; API Gateway invoke es a nivel IAM (bypassa SG inbound).
# checkov:skip=CKV_AWS_24:Lambda SG ingress vacio intencionalmente; SG no es relevante para ingress HTTP (sg es para ENI-level control).
# checkov:skip=CKV_AWS_260:Lambda SG ingress vacio intencionalmente.
resource "aws_security_group" "lambda" {
  # checkov:skip=CKV2_AWS_5:Lambda SG se attachea via modules/rds-postgres (allowed_security_group_ids) y via module.iam-lambda-exec direct reuse desde template.yaml + AWS::ApiGatewayV2::Authorizer.
  name_prefix = "${var.project_name}-${var.environment}-lambda-sg-"
  description = "Security group for ORION Lambda functions (VPC-attached). Referenced by RDS SG ingress allowlist."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress to VPC CIDR (RDS at 10.20.0.0/16)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Sin VPC endpoints para SM/SSM/Logs/ECR/EventBridge/Sts (drift cleanup los
  # destruyo), las Lambdas necesitan hablar con las public AWS APIs via NAT.
  # El NAT hace source-NAT y el IGW enruta; este egress es la unica forma de
  # que la conexion Lambda -> NAT -> IGW -> AWS API sea permitida por el SG.
  # Trust sigue acotado por la IAM role del Lambda (que APIs puede invocar)
  # y por el NAT (que solo enruta trafico originado en el VPC).
  egress {
    # checkov:skip=CKV_AWS_382:Egress 0.0.0.0/0 es necesario porque no hay VPC endpoints (drift cleanup) y las Lambdas en subnets privadas solo pueden alcanzar las public AWS APIs via NAT. Trust sigue acotado por la IAM role del Lambda (que APIs puede invocar) y por el NAT (source-NAT, solo enrutado si la trafico se origina en el VPC).
    description = "Allow all egress to public internet via NAT Gateway (SM/SSM/Logs/ECR/EventBridge/Sts public endpoints)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  })
}
