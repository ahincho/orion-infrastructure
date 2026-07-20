###############################################################################
# Data sources
# -----------------------------------------------------------------------------
# AWS account + region necesarias para construir ARN-templates parametrizados
# en data.aws_iam_policy_document (CloudWatch Logs).
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

###############################################################################
# Trust policy: Bedrock AgentCore service principal
# -----------------------------------------------------------------------------
# El role solo puede ser assumido por el servicio bedrock-agentcore.amazonaws.com
# (no por usuarios humanos). Si var.runtime_arn viene provisto, se agrega la
# condition `aws:SourceArn` para restringir el assume a un runtime concreto
# (defense in depth anti-confused-deputy). Si esta vacio (default), cualquier
# AgentRuntime de la cuenta puede assumir (looser, util durante el bootstrap
# antes de crear el runtime en si).
###############################################################################
data "aws_iam_policy_document" "trust" {
  # checkov:skip=CKV_AWS_60:Trust policy solo admite el service principal bedrock-agentcore.amazonaws.com, no requiere permissions boundary (los IAM users humanos no pueden assumir este role por diseno).
  # checkov:skip=CKV_AWS_61:No requiere sts:SourceIdentity porque el caller es un servicio AWS, no un ser humano con identidad discreta.
  # checkov:skip=CKV_AWS_107:Service principal no requiere sts:ExternalValidation; la cuenta AWS ya esta autenticada por la firma SigV4.
  # checkov:skip=CKV_AWS_358:No aplica captcha al flow de servicios; el assume es server-to-server.
  statement {
    sid     = "BedrockAgentCoreServiceAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    # Condition opcional: solo presente si var.runtime_arn != "".
    dynamic "condition" {
      for_each = var.runtime_arn != "" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [var.runtime_arn]
      }
    }
  }
}

###############################################################################
# Inline permissions policy para OrionAgentCoreRuntime
# -----------------------------------------------------------------------------
# Permisos minimos para el contenedor del runtime:
#   1. bedrock:InvokeModel + Converse* (cualquier model ARN; se especifica en
#      el campo environment_variables del AgentRuntime en runtime module).
#   2. logs:CreateLogGroup/Stream + PutLogEvents + Describe* sobre el prefijo
#      /aws/bedrock-agentcore/<runtime-name>.
###############################################################################
data "aws_iam_policy_document" "orion_agent_core_runtime_inline" {
  # checkov:skip=CKV_AWS_109:El role solo puede ser assumido por el servicio bedrock-agentcore.amazonaws.com (no por usuarios), por lo que no requiere condicion aws:CalledViaFirstAuthenticated additional.
  # checkov:skip=CKV_AWS_111:No requiere operaciones IAM auditadas; el container no tiene permisos para crear/modificar IAM resources.
  # checkov:skip=CKV_AWS_290:El trust esta restringido al service principal; sin acceso publico.
  # checkov:skip=CKV_AWS_355:Project tag propagado a todos los recursos via default_tags del provider.
  # checkov:skip=CKV_AWS_356:Acciones con Resource: * son bedrock:InvokeModel/Converse (acciones API-level no restrictable por recurso individual en el modelo de AWS; el control fino se hace via condition aws:ResourceTag/Project en futuras iteraciones si es necesario).

  # Bedrock model invocations (inference runtime).
  statement {
    sid    = "BedrockInvokeModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    resources = ["*"]
  }

  # CloudWatch logs del runtime (logs entregados automaticamente por AgentCore
  # bajo el prefijo /aws/bedrock-agentcore/<runtime-name>; el container
  # necesita poder emitir metrica adicionales en este grupo).
  statement {
    sid    = "CloudWatchLogsForAgentRuntime"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*",
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*:*",
    ]
  }
}

###############################################################################
# Resources
###############################################################################
resource "aws_iam_role" "orion_agent_core_runtime" {
  # checkov:skip=CKV_AWS_356:Trust policy restringida al service principal bedrock-agentcore.amazonaws.com (no human-assumable), por lo que las recomendaciones de CKV_AWS_356 (scope por tag/ARN en trust) no aplican.
  name                 = "${var.project_name}-agent-core-runtime-${var.environment}"
  description          = "Role assumido por el contenedor de OrionAgentCore dentro del Bedrock AgentCore Runtime en ${var.environment}. Permisos minimos: Bedrock InvokeModel + CloudWatch logs."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600 # 1h max.

  tags = merge(var.tags, {
    Name      = "${var.project_name}-agent-core-runtime-${var.environment}"
    Purpose   = "OrionAgentCoreRuntime"
    Component = "iam"
  })
}

resource "aws_iam_role_policy" "orion_agent_core_runtime_inline" {
  name   = "${var.project_name}-agent-core-runtime-${var.environment}-inline"
  role   = aws_iam_role.orion_agent_core_runtime.id
  policy = data.aws_iam_policy_document.orion_agent_core_runtime_inline.json
}
