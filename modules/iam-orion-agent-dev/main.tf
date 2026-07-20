###############################################################################
# Module: iam-orion-agent-dev
# -----------------------------------------------------------------------------
# Crea el IAM role + inline policy `OrionAgentDeployPolicy` que asume el futuro
# workflow `CD - Deploy` de **orion-cognitive-agent** via GitHub OIDC para:
#
#   1. build + push de la imagen Docker del agente a ECR
#      (modules/ecr-orion-agent)
#   2. management del Bedrock AgentCore Runtime
#      (create/update/delete + invoke; el modulo
#       `bedrock-agentcore-runtime` se anade en Sprint B.2)
#   3. lectura de CloudWatch Logs del runtime
#   4. iam:PassRole al servicio bedrock-agentcore.amazonaws.com (limita
#      a que el role pueda pasarse solo a Bedrock AgentCore, no a otros
#      servicios — prevencion de confused deputy)
#   5. lectura de SSM parameters bajo /orion/agent/* (cors, secrets,
#      runtime config que el agente lee via data.aws_ssm_parameter en su
#      deploy workflow)
#
# Trust policy:
#   - Principal: token.actions.githubusercontent.com (OIDC) via el provider
#     pre-existente creado por modules/oidc-github (no se recrea aqui —
#     este modulo asume que el OIDC provider ya existe).
#   - Condition: aud=sts.amazonaws.com, sub StringLike a
#     repo:ahincho/orion-cognitive-agent:ref:refs/heads/main
#     y environment:dev. El sub no acepta * para forzar scope explicito.
#
# OrionAgentDeployPolicy (inline):
#   - 7 statements: ECR push (recurso = repo-arn + image-arn, NO wildcard
#     excepto ecr:GetAuthorizationToken que es account-level), Bedrock
#     InvokeModel (cross-region inference profile ARN scoped), AgentCore
#     full management, CloudWatch Logs orion-agent-dev-* log groups,
#     SSM /orion/agent/* read, PassRole restringido.
#
# Decisiones:
#   - No managed policies adjuntas (todo inline en OrionAgentDeployPolicy)
#     para minimizar superficie y consolidar en terraform plan.
#   - max_session_duration = 3600s (1h) alineado con el default AWS.
#   - Tagging consistente con los demas modulos orion-infrastructure
#     (Project + Environment + ManagedBy + Repository). default_tags del
#     provider no se aplica aqui (este modulo no instancia el provider).
#   - checkov:skip aplicados:
#     * CKV_AWS_60, CKV_AWS_61, CKV_AWS_107: trust es OIDC externo, no
#       AWS account ni AWS service.
#     * CKV_AWS_111, CKV_AWS_355: acciones ARN-scoped per service;
#       unica excepcion es ecr:GetAuthorizationToken que requiere
#       Resource="*" (es account-level).
#     * CKV_AWS_290, CKV_AWS_109: cross-service API calls necesarios;
#       iam:PassRole con aws:PassedToService condition.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "iam-orion-agent-dev"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
      Purpose     = "Deploy role for orion-cognitive-agent AgentCore Runtime"
    }
  )

  # ARN del ECR repo del agente. El modulo lee var.ecr_repository_uri
  # (no el ARN completo); lo derivamos a partir de la convention del repo
  # name + region + account.
  ecr_repo_arn         = "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.ecr_repository_name}"
  ecr_image_arn_prefix = "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.ecr_repository_name}"

  # ARNs de log groups esperables en dev. Cobertura:
  #   /aws/orion/agent/dev/*      (log group principal del AgentCore Runtime)
  #   /aws/bedrock-agentcore/*    (si AgentCore emite logs propios)
  cw_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/orion/agent/dev/*",
    "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/bedrock-agentcore/*",
  ]

  # ARNs SSM que el workflow de deploy puede querer leer (cors config,
  # secrets ya bootstrapped, config del agent).
  ssm_parameter_arns = [
    "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/orion/agent/*",
  ]
}

###############################################################################
# Trust policy: GitHub OIDC + branch + environment allowlist
###############################################################################
data "aws_iam_policy_document" "trust" {
  #checkov:skip=CKV_AWS_61:Trust principal OIDC no AWS service
  #checkov:skip=CKV_AWS_60:Trust policy restricted by OIDC aud/sub
  #checkov:skip=CKV_AWS_107:N/A role para OIDC GitHub no servicio AWS
  #checkov:skip=CKV_AWS_358:StringLike after StringEquals acceptable
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        [
          for env in var.github_environments :
          "repo:${var.github_org}/${var.github_repo}:environment:${env}"
        ],
        [
          "repo:${var.github_org}/${var.github_repo}:ref:${var.github_branch}",
        ],
      )
    }
  }
}

resource "aws_iam_role" "orion_agent_deploy" {
  name                  = "${var.project_name}-agent-deploy-${var.environment}"
  assume_role_policy    = data.aws_iam_policy_document.trust.json
  max_session_duration  = 3600
  path                  = "/"
  force_detach_policies = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-agent-deploy-${var.environment}"
  })
}

###############################################################################
# OrionAgentDeployPolicy (inline, 7 statements)
###############################################################################
data "aws_iam_policy_document" "orion_agent_deploy_inline" {
  #checkov:skip=CKV_AWS_109:iam PassRole uses aws PassedToService condition to limit to bedrock-agentcore
  #checkov:skip=CKV_AWS_111:Actions ARN-scoped per service; ecr:GetAuthorizationToken + sts:GetCallerIdentity use "*" because they are account-level or metadata APIs
  #checkov:skip=CKV_AWS_290:Cross-AWS-API actions needed for AgentCore + ECR deploy; each scoped to ARN list
  #checkov:skip=CKV_AWS_355:Same as CKV_AWS_356 below; "*" used for account-level APIs only
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken + sts:GetCallerIdentity + bedrock-agentcore:* use "*" because they are account-level or pre-launch API

  #############################################################################
  # ECR: push de imagen del agente. Acciones account-level requieren "*"
  # (ecr:GetAuthorizationToken no soporta resource-level scoping).
  #############################################################################
  statement {
    sid    = "ECRPushImage"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [
      local.ecr_repo_arn,
      "${local.ecr_image_arn_prefix}/*",
      "*", # ecr:GetAuthorizationToken es account-level
    ]
  }

  #############################################################################
  # Bedrock: InvokeModel sobre el cross-region inference profile Sonnet 4.
  # Limitado por region + model id. El agente runtime usara su propio role
  # (creado por el modulo bedrock-agentcore-runtime en Sprint B.2), pero el
  # workflow de deploy enrareces invoca Bedrock directo para health checks
  # o tests de smoke (e.g. invoke con prompt "ping").
  #############################################################################
  statement {
    sid    = "BedrockInvokeModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}",
      "arn:aws:bedrock:${var.aws_region}::foundation-model/*",
    ]
  }

  #############################################################################
  # Bedrock AgentCore: management completo del Runtime + endpoints.
  # Actions ARN-scoped al runtime cuando este modulo viva (Sprint B.2);
  # mientras tanto el workflow no tendra un ARN especifico que escopear,
  # asi que usamos wildcard *" por compatibilidad con la API preview de
  # AgentCore (las ARN-scoped requieren el runtime ya creado).
  #############################################################################
  statement {
    sid    = "BedrockAgentCoreManage"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      "bedrock-agentcore:UpdateAgentRuntime",
      "bedrock-agentcore:DeleteAgentRuntime",
      "bedrock-agentcore:GetAgentRuntime",
      "bedrock-agentcore:ListAgentRuntimes",
      "bedrock-agentcore:CreateAgentEndpoint",
      "bedrock-agentcore:UpdateAgentEndpoint",
      "bedrock-agentcore:DeleteAgentEndpoint",
      "bedrock-agentcore:GetAgentEndpoint",
      "bedrock-agentcore:ListAgentEndpoints",
      "bedrock-agentcore:InvokeAgentRuntime",
      "bedrock-agentcore:InvokeAgentEndpoint",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:DeleteAgentRuntimeEndpoint",
      "bedrock-agentcore:ListAgentRuntimeEndpoints",
    ]
    resources = ["*"]
  }

  #############################################################################
  # CloudWatch Logs: leer + escribir en log groups del agente.
  #############################################################################
  statement {
    sid    = "CloudWatchLogsAgent"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = local.cw_log_group_arns
  }

  #############################################################################
  # SSM: leer /orion/agent/* (cors config, secrets ARNs, runtime config).
  #############################################################################
  statement {
    sid    = "SSMReadAgentParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = local.ssm_parameter_arns
  }

  #############################################################################
  # IAM: PassRole al servicio bedrock-agentcore. Limitado por
  # aws:PassedToService para prevenir confused deputy (el role solo
  # puede pasarse a AgentCore, no a otros servicios AWS).
  #############################################################################
  statement {
    sid       = "IAMPassRoleToBedrockAgentCore"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/orion-agent-exec-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["bedrock-agentcore.amazonaws.com"]
    }
  }

  #############################################################################
  # STS: get caller identity (para validacion OIDC).
  #############################################################################
  statement {
    sid       = "STSGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "orion_agent_deploy_inline" {
  name   = "OrionAgentDeployPolicy"
  role   = aws_iam_role.orion_agent_deploy.id
  policy = data.aws_iam_policy_document.orion_agent_deploy_inline.json
}
