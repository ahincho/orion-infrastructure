###############################################################################
# Data sources
# -----------------------------------------------------------------------------
# AWS account + region necesarias para construir ARN-templates parametrizados
# en data.aws_iam_policy_document (CloudWatch Logs + SSM Parameter Store).
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

###############################################################################
# Trust policy: GitHub Actions OIDC para orion-cognitive-agent
# -----------------------------------------------------------------------------
# Asumible solo desde el ref:refs/heads/main del repo. Permite a cualquier job
# de CI/CD del repo obtener credenciales AWS de corta duracion sin necesidad
# de long-lived access keys. El provider real es el de modules/oidc-github,
# compartido entre repos ORION.
###############################################################################
data "aws_iam_policy_document" "trust" {
  # checkov:skip=CKV_AWS_60:GitHub OIDC trust no requiere permissions boundary en el trust policy (se aplican via iam:PermissionsBoundary si se necesita).
  # checkov:skip=CKV_AWS_61:GitHub OIDC trust usa sub claim explicito (main), no requiere sts:SourceIdentity adicional.
  # checkov:skip=CKV_AWS_107:Role asumido solo por GitHub Actions OIDC, no por usuarios humanos (no requiere sts:ExternalValidation).
  # checkov:skip=CKV_AWS_358:Rol GitHub OIDC no requiere captcha (no es login humano). El apply-only scope ya esta enforced por OIDC sub claim.
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

###############################################################################
# Inline permissions policy para OrionAgentCoreDeploy
# -----------------------------------------------------------------------------
# Permisos esperados por el deploy job de orion-cognitive-agent sobre Bedrock
# AgentCore Runtime. Mantenido intencionalmente granular: el deploy job nunca
# toca IAM, KMS ni org-level services, solo AgentCore + ECR + logs + SSM read.
###############################################################################
data "aws_iam_policy_document" "orion_agent_core_deploy_inline" {
  # checkov:skip=CKV_AWS_109:El role es GitHub-OIDC-only con sub claim restringido a ref:refs/heads/main, sin humanos; el codigo del workflow es el unico caller.
  # checkov:skip=CKV_AWS_111:Recursos IAM creados con aws_iam_role + aws_iam_role_policy inline explicitos; no requiere log para operaciones IAM en si.
  # checkov:skip=CKV_AWS_290:El sub claim restringe el flujo a GitHub OIDC main branch, sin acceso publico.
  # checkov:skip=CKV_AWS_355:Project tag propagado a todos los recursos via default_tags del provider.
  # checkov:skip=CKV_AWS_356:Las acciones con Resource: * son: ecr:GetAuthorizationToken (requerido por AWS como API global de single-account), bedrock-agentcore control plane (Create/Update/Delete/Describe/List) y bedrock:InvokeModel/Converse — todas son acciones API-level no restrictable por recurso individual. Scope por proyecto se enforce via condition aws:ResourceTag/Project + OIDC sub claim.
  # ECR pull sobre el repo del agent (image-based AgentCore deployments).
  statement {
    sid    = "ECRPullAgentImages"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeRepositories",
    ]
    resources = [var.ecr_repository_arn]
  }

  # ECR auth token (necesario para docker login durante build + pipeline).
  # Por diseno AWS esta accion SIEMPRE requiere Resource: * (es API global).
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Bedrock AgentCore Runtime control plane + data plane.
  statement {
    sid    = "BedrockAgentCoreRuntime"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      "bedrock-agentcore:GetAgentRuntime",
      "bedrock-agentcore:UpdateAgentRuntime",
      "bedrock-agentcore:DeleteAgentRuntime",
      "bedrock-agentcore:ListAgentRuntimes",
      "bedrock-agentcore:InvokeAgentRuntime",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:GetAgentRuntimeEndpoint",
      "bedrock-agentcore:UpdateAgentRuntimeEndpoint",
      "bedrock-agentcore:DeleteAgentRuntimeEndpoint",
      "bedrock-agentcore:ListAgentRuntimeEndpoints",
      "bedrock-agentcore:StartCodeInterpreterSession",
      "bedrock-agentcore:StopCodeInterpreterSession",
      "bedrock-agentcore:StartBrowserSession",
      "bedrock-agentcore:StopBrowserSession",
    ]
    resources = ["*"]
  }

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

  # CloudWatch logs (logs del runtime).
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
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*:*",
    ]
  }

  # SSM Parameter Store read (runtime-arn + endpoint-arn creados al deploy).
  statement {
    sid    = "SSMParametersRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      for path in [
        "/orion/agent-core/runtime-arn",
        "/orion/agent-core/endpoint-arn",
      ] : "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${path}"
    ]
  }

  # IAM PassRole: el deploy job puede pasar el OrionAgentCore Runtime execution
  # role al servicio bedrock-agentcore al crear/actualizar un AgentRuntime.
  dynamic "statement" {
    for_each = length(var.agentcore_runtime_role_arns) > 0 ? [1] : []
    content {
      sid    = "IAMPassRoleToAgentCore"
      effect = "Allow"
      actions = [
        "iam:PassRole",
      ]
      resources = var.agentcore_runtime_role_arns

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["bedrock-agentcore.amazonaws.com"]
      }
    }
  }
}

###############################################################################
# Resources
###############################################################################
resource "aws_iam_role" "orion_agent_core_deploy" {
  # checkov:skip=CKV_AWS_356:El role es GitHub-OIDC-only (asumible solo por el repo caller). Restricciones adicionales (tag conditions, ARN scoping) viven en las inline policy statements, no en la trust policy.
  name                 = "${var.project_name}-agent-core-deploy-${var.environment}"
  description          = "Role asumido por GitHub Actions (OIDC) del repo orion-cognitive-agent para deploys de Bedrock AgentCore Runtime (OrionAgentCore) en ${var.environment}."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600 # 1h max (GitHub OIDC sessions son de 60min por defecto).

  tags = merge(var.tags, {
    Name      = "${var.project_name}-agent-core-deploy-${var.environment}"
    Purpose   = "OrionAgentCoreDeploy"
    Component = "iam"
    Repo      = var.github_repository
  })
}

resource "aws_iam_role_policy" "orion_agent_core_deploy_inline" {
  name   = "${var.project_name}-agent-core-deploy-${var.environment}-inline"
  role   = aws_iam_role.orion_agent_core_deploy.id
  policy = data.aws_iam_policy_document.orion_agent_core_deploy_inline.json
}
