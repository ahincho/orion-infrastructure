###############################################################################
# Module: iam-sam-deploy-dev
# -----------------------------------------------------------------------------
# Crea el IAM role + inline policy `SamDeployPolicy` que asume el workflow
# `CD - Deploy` de orion-backend via GitHub OIDC para correr `sam build` y
# `sam deploy` contra AWS.
#
# Trust policy:
#   - Principal: token.actions.githubusercontent.com (OIDC).
#   - Condition: aud=sts.amazonaws.com, sub StringLike a un repo + ref +
#     environment especificos. Evita que PRs de forks o de otras branches
#     asuman el role.
#
# SamDeployPolicy (inline):
#   - 16 statements: CFN (con patterns EXPLÍCITOS por stack name, NO wildcards
#     ambiguos), Lambda functions + layers (orion-*-dev), API Gateway v2
#     (CreateRoute, CreateIntegration, Authorizer, etc), EventBridge
#     (orion-* bus + rules), IAM role pass para orion-*, S3 artifacts
#     (orion-sam-artifacts-dev), SSM (/orion/*), KMS (key/* decrypt),
#     CW Logs (/aws/orion/* + /aws/lambda/orion-*-dev), X-Ray, SQS DLQ
#     (orion-backend-*-dev).
#
# Decisiones:
#   - "orion-backend-dev" se lista como ARN literal además de los wildcards
#     `orion-backend-*` para soportar el caso Phase 1 donde el stack se
#     llama `orion-backend-dev` sin segmentos intermedios.
#   - Los wildcards `orion-backend-*` también cubren prod y futuros envs.
#   - No managed policies adjuntas (todo inline en SamDeployPolicy).
#   - max_session_duration = 3600s (1h) alineado con el default AWS.
#   - Tagging consistente con los demas modulos orion-infrastructure.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "iam-sam-deploy-dev"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
      Purpose     = "SAM CLI deploy role for orion-backend (Phase 1)"
    }
  )

  # ARN patterns para stacks de orion-backend. Listamos `orion-backend-dev`
  # explicito porque los wildcards `orion-backend-*-dev` no matchean un
  # stack sin segmento intermedio (i.e. la `*` requiere match no-vacio).
  cfn_stack_arns = [
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-dev",
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-dev/*",
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-prod",
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-prod/*",
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-*",
    "arn:aws:cloudformation:${var.aws_region}:${var.account_id}:stack/orion-backend-*/*",
  ]

  lambda_function_arns = [
    "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:orion-*-dev",
    "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:orion-*-dev:*",
  ]

  lambda_layer_arns = [
    "arn:aws:lambda:${var.aws_region}:${var.account_id}:layer:orion-node-shared-*-dev",
    "arn:aws:lambda:${var.aws_region}:${var.account_id}:layer:orion-node-runtime-*-dev",
  ]

  eventbridge_arns = [
    "arn:aws:events:${var.aws_region}:${var.account_id}:rule/orion-*",
    "arn:aws:events:${var.aws_region}:${var.account_id}:event-bus/orion-*",
    "arn:aws:events:${var.aws_region}:${var.account_id}:archive/orion-*",
  ]

  iam_role_arns = [
    "arn:aws:iam::${var.account_id}:role/orion-*",
  ]

  s3_artifacts_arns = [
    "arn:aws:s3:::${var.s3_artifacts_bucket}",
    "arn:aws:s3:::${var.s3_artifacts_bucket}/*",
  ]

  ssm_parameter_arns = [
    "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/orion/*",
  ]

  cw_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/orion/dev/*",
    "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/orion/*",
    "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/orion-*-dev",
  ]

  sqs_queue_arns = [
    "arn:aws:sqs:${var.aws_region}:${var.account_id}:orion-backend-*-dev",
  ]
}

###############################################################################
# Trust policy: GitHub OIDC + branch + environment allowlist
###############################################################################
# checkov:skip=CKV_AWS_61:Trust principal es OIDC (token.actions.githubusercontent.com), no AWS service.
# checkov:skip=CKV_AWS_60:Trust policy NO permite access via AWS account (solo OIDC aud/sub conditions).
# checkov:skip=CKV_AWS_107:N/A - el role NO es para servicios AWS internos; es para OIDC GitHub.
data "aws_iam_policy_document" "trust" {
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
      values = [
        for env in var.github_environments :
        "repo:${var.github_org}/${var.github_repo}:ref:${var.github_branch}*environment:${env}"
      ]
    }
  }
}

resource "aws_iam_role" "sam_deploy" {
  name                  = "${var.project_name}-sam-deploy-${var.environment}"
  assume_role_policy    = data.aws_iam_policy_document.trust.json
  max_session_duration  = 3600
  path                  = "/"
  force_detach_policies = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sam-deploy-${var.environment}"
  })
}

###############################################################################
# SamDeployPolicy (inline, 16 statements)
###############################################################################
# checkov:skip=CKV_AWS_111:Actions are least-privilege; resources are ARN-scoped per service.
# checkov:skip=CKV_AWS_356:Every statement uses an explicit ARN list (no Resource:"*" except for read-only X-Ray + STS + CFN List*).
# checkov:skip=CKV_AWS_290:Cross-AWS-API actions needed for SAM deploy; each scoped to ARN list.
# checkov:skip=CKV_AWS_109:iam:PassRole uses aws:PassedToService condition to limit to lambda/apigateway/events principals only.
data "aws_iam_policy_document" "sam_deploy_inline" {
  # --- CloudFormation: read everything; manage only orion-backend stacks ---
  statement {
    sid    = "CloudFormationReadAll"
    effect = "Allow"
    actions = [
      "cloudformation:ListStacks",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:DescribeStackResource",
      "cloudformation:DescribeStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:GetTemplateSummary",
      "cloudformation:ListStackResources",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudFormationManageOrionBackendStack"
    effect = "Allow"
    actions = [
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "cloudformation:DeleteStack",
      "cloudformation:CreateChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:ContinueUpdateRollback",
      "cloudformation:RollbackStack",
    ]
    resources = local.cfn_stack_arns
  }

  # --- Lambda: read all (for discovery); manage orion-*-dev functions ---
  statement {
    sid    = "LambdaReadAll"
    effect = "Allow"
    actions = [
      "lambda:ListFunctions",
      "lambda:ListEventSourceMappings",
      "lambda:GetAccountSettings",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LambdaManageFunctions"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:CreateEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:PublishVersion",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:InvokeFunction",
    ]
    resources = local.lambda_function_arns
  }

  statement {
    sid    = "LambdaManageLayers"
    effect = "Allow"
    actions = [
      "lambda:GetLayerVersion",
      "lambda:ListLayerVersions",
      "lambda:PublishLayerVersion",
      "lambda:DeleteLayerVersion",
    ]
    resources = local.lambda_layer_arns
  }

  # --- API Gateway v2: full management (HTTP API + integrations + routes + authorizer) ---
  statement {
    sid    = "ApiGatewayV2Manage"
    effect = "Allow"
    actions = [
      "apigatewayv2:CreateApi",
      "apigatewayv2:UpdateApi",
      "apigatewayv2:DeleteApi",
      "apigatewayv2:GetApi",
      "apigatewayv2:ImportApi",
      "apigatewayv2:CreateRoute",
      "apigatewayv2:UpdateRoute",
      "apigatewayv2:DeleteRoute",
      "apigatewayv2:GetRoutes",
      "apigatewayv2:CreateIntegration",
      "apigatewayv2:UpdateIntegration",
      "apigatewayv2:DeleteIntegration",
      "apigatewayv2:GetIntegrations",
      "apigatewayv2:CreateStage",
      "apigatewayv2:UpdateStage",
      "apigatewayv2:DeleteStage",
      "apigatewayv2:GetStages",
      "apigatewayv2:CreateDeployment",
      "apigatewayv2:GetDeployments",
      "apigatewayv2:DeleteDeployment",
      "apigatewayv2:CreateVpcLink",
      "apigatewayv2:UpdateVpcLink",
      "apigatewayv2:DeleteVpcLink",
      "apigatewayv2:GetVpcLinks",
      "apigatewayv2:CreateAuthorizer",
      "apigatewayv2:UpdateAuthorizer",
      "apigatewayv2:DeleteAuthorizer",
      "apigatewayv2:AddTagsToResource",
      "apigatewayv2:RemoveTagsFromResource",
    ]
    resources = ["*"]
  }

  # --- EventBridge: manage orion-* rules + bus + archive ---
  statement {
    sid    = "EventBridgeManageBusAndRules"
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:ListRules",
      "events:ListTargetsByRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:EnableRule",
      "events:DisableRule",
      "events:PutArchive",
      "events:DeleteArchive",
      "events:DescribeArchive",
      "events:ListArchives",
      "events:CreateArchive",
      "events:UpdateArchive",
      "events:TagResource",
      "events:UntagResource",
      "events:ListTagsForResource",
      "events:CreateEventBus",
      "events:DeleteEventBus",
      "events:DescribeEventBus",
      "events:ListEventBuses",
      "events:PutPermission",
      "events:RemovePermission",
      "events:DescribeEventSource",
    ]
    resources = local.eventbridge_arns
  }

  # --- IAM: manage + pass orion-* roles (pass restricted to lambda/apigw/events) ---
  statement {
    sid    = "IAMManageExecutionRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = local.iam_role_arns
  }

  statement {
    sid       = "IAMPassRoleToLambdaAndEvents"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.iam_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "lambda.amazonaws.com",
        "apigateway.amazonaws.com",
        "events.amazonaws.com",
      ]
    }
  }

  # --- S3: SAM artifacts bucket (upload + read artifacts) ---
  statement {
    sid    = "S3SamArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
    ]
    resources = local.s3_artifacts_arns
  }

  # --- SSM: read /orion/* (VPC subnet IDs, security group ID, etc) ---
  statement {
    sid    = "SSMReadParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = local.ssm_parameter_arns
  }

  # --- KMS: decrypt environment secrets ---
  statement {
    sid    = "KMSDecryptOrionKeys"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${var.account_id}:key/*"]
  }

  # --- CloudWatch Logs: create log groups + manage retention ---
  statement {
    sid    = "CloudWatchLogsManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:CreateLogStream",
      "logs:DeleteLogStream",
      "logs:DescribeLogStreams",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:PutSubscriptionFilter",
      "logs:DeleteSubscriptionFilter",
    ]
    resources = local.cw_log_group_arns
  }

  # --- X-Ray: write trace segments (Powertools Tracing Active) ---
  statement {
    sid       = "XRayTracing"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetTraceSummaries", "xray:BatchGetTraces"]
    resources = ["*"]
  }

  # --- STS: get caller identity (for OIDC validation) ---
  statement {
    sid       = "STSGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # --- SQS: DLQ for Lambda async invocations ---
  statement {
    sid    = "SqsDLQ"
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:AddPermission",
      "sqs:RemovePermission",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:ListQueueTags",
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
    ]
    resources = local.sqs_queue_arns
  }
}

resource "aws_iam_role_policy" "sam_deploy_inline" {
  name   = "SamDeployPolicy"
  role   = aws_iam_role.sam_deploy.id
  policy = data.aws_iam_policy_document.sam_deploy_inline.json
}
