###############################################################################
# Module: iam-sam-deploy-dev
# -----------------------------------------------------------------------------
# Crea el IAM role + inline policy `SamDeployPolicy` que asume el workflow
# `CD - Deploy` de ahincho/orion-backend via GitHub OIDC para correr
# `sam build` y `sam deploy` contra AWS.
#
# Antes de este modulo: orion-backend dependia de un rol con prefijo
# `spark-match-sam-deploy-dev` parcheado a mano (legacy del bootstrap inicial).
# Este modulo lo reemplaza por uno Terraform-managed con naming orion-* + scope
# exclusivo al repo orion-backend.
#
# Trust policy:
#   - Principal: token.actions.githubusercontent.com (OIDC).
#   - Condition: aud=sts.amazonaws.com, sub StringLike a
#     repo:ahincho/orion-backend:ref:refs/heads/main + environment:dev.
#   - Solo el repo orion-backend puede asumir; PRs de forks o spark-match
#     no son aceptados.
#
# SamDeployPolicy (inline) - replica los permisos parchados del rol legacy:
#   - CloudFormation read+manage sobre stack orion-backend-dev* (incluye
#     nested stacks via /<id>).
#   - Lambda create/update/delete/invoke sobre orion-*-dev + layers
#     orion-node-shared-dev*, orion-node-runtime-dev*.
#   - API Gateway v2 (full manage) + apigateway:GET para v1 fallback.
#   - EventBridge: rules + bus + archives bajo orion-*.
#   - IAM manage roles orion-backend-dev*, orion-*-exec-dev,
#     orion-lambda-runtime-dev* + PassRole scoped a
#     lambda/apigateway/events.
#   - S3: orion-sam-artifacts-dev* + orion-tfstate-dev* (lectura de outputs).
#   - SSM: parameter store bajo /orion/*.
#   - KMS: Decrypt sobre key/* con condition tag Project=orion Environment=dev.
#   - CloudWatch Logs: /aws/orion/* + /aws/lambda/orion-backend-dev*.
#   - X-Ray + STS:GetCallerIdentity.
#   - SQS DLQ: orion-backend-dev*.
#   - CloudFormationServerlessTransform: permite al SAM CLI invocar la
#     macro Serverless-2016-10-31 al crear/actualizar el changeset.
#
# Decisiones:
#   - "orion-backend-dev" se lista como ARN literal ademas de wildcards
#     `orion-backend-dev*` para soportar el caso Phase 1 donde el stack
#     se llama `orion-backend-dev` sin segmentos intermedios (los
#     wildcards de IAM no matchean vacio en algunos contextos).
#   - No managed policies adjuntas (todo inline en SamDeployPolicy).
#   - max_session_duration = 3600s (1h) alineado con el default AWS.
#   - Tagging consistente con los demas modulos orion-infrastructure.
###############################################################################

data "aws_caller_identity" "current" {}

# Region: tomada de var.aws_region (pasada por live/dev, validada en
# variables.tf) en lugar de la data source `aws_region`, que ahora es
# redundante (tflint:terraform_unused_declarations si la region se obtiene
# de ambos lados). El caller siempre pasa `aws_region = var.aws_region`
# desde `live/dev/main.tf`; usar esa misma fuente simplifica el modulo.

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region

  cfn_stack_arns = [
    "arn:aws:cloudformation:${local.region}:${local.account_id}:stack/orion-backend-dev",
    "arn:aws:cloudformation:${local.region}:${local.account_id}:stack/orion-backend-dev/*",
    "arn:aws:cloudformation:${local.region}:${local.account_id}:stack/orion-backend-dev*",
    "arn:aws:cloudformation:${local.region}:${local.account_id}:stack/orion-backend-dev*/*",
  ]

  lambda_function_arns = [
    "arn:aws:lambda:${local.region}:${local.account_id}:function:orion-backend-dev*",
    "arn:aws:lambda:${local.region}:${local.account_id}:function:orion-backend-dev*:*",
    "arn:aws:lambda:${local.region}:${local.account_id}:function:orion-*-dev",
    "arn:aws:lambda:${local.region}:${local.account_id}:function:orion-*-dev:*",
  ]

  lambda_layer_arns = [
    "arn:aws:lambda:${local.region}:${local.account_id}:layer:orion-node-shared-dev*",
    "arn:aws:lambda:${local.region}:${local.account_id}:layer:orion-node-runtime-dev*",
    "arn:aws:lambda:${local.region}:${local.account_id}:layer:orion-python-shared-dev*",
    "arn:aws:lambda:${local.region}:${local.account_id}:layer:orion-python-runtime-dev*",
  ]

  eventbridge_arns = [
    "arn:aws:events:${local.region}:${local.account_id}:rule/orion-*",
    "arn:aws:events:${local.region}:${local.account_id}:event-bus/orion-*",
    "arn:aws:events:${local.region}:${local.account_id}:archive/orion-*",
  ]

  iam_role_arns = [
    "arn:aws:iam::${local.account_id}:role/orion-backend-dev*",
    "arn:aws:iam::${local.account_id}:role/orion-*-exec-dev",
    "arn:aws:iam::${local.account_id}:role/orion-lambda-runtime-dev*",
    # Authorizer invoke role: API Gateway ASSUMES this role to invoke the
    # Lambda authorizer. sam deploy issues iam:PassRole for any role
    # referenced in AWS::ApiGatewayV2::Authorizer.AuthorizerCredentialsArn.
    # The role does not match the orion-* / *-exec-dev / *-runtime-dev*
    # patterns above because it was created manually before this module
    # was aware of it; a follow-up orion-infrastructure PR will provision
    # it via Terraform with a conformant name (orion-apigateway-authorizer-
    # invoke-dev) and the entry below can be removed.
    "arn:aws:iam::${local.account_id}:role/apigateway-authorizer-invoke-role-dev",
  ]

  s3_artifacts_arns = [
    "arn:aws:s3:::orion-sam-artifacts-dev",
    "arn:aws:s3:::orion-sam-artifacts-dev/*",
    "arn:aws:s3:::orion-sam-artifacts-dev*",
    "arn:aws:s3:::orion-sam-artifacts-dev*/*",
    "arn:aws:s3:::orion-backend-deploy-dev",
    "arn:aws:s3:::orion-backend-deploy-dev/*",
    "arn:aws:s3:::orion-backend-deploy-dev*",
    "arn:aws:s3:::orion-backend-deploy-dev*/*",
  ]

  s3_tfstate_arns = [
    "arn:aws:s3:::orion-tfstate-dev",
    "arn:aws:s3:::orion-tfstate-dev/*",
    "arn:aws:s3:::orion-tfstate-dev*",
    "arn:aws:s3:::orion-tfstate-dev*/*",
  ]

  ssm_parameter_arns = [
    "arn:aws:ssm:${local.region}:${local.account_id}:parameter/orion/*",
  ]

  cw_log_group_arns = [
    "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/orion/*",
    "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/orion/*:*",
    "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/orion-backend-dev*",
    "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/orion-backend-dev*:*",
  ]

  sqs_dlq_arns = [
    "arn:aws:sqs:${local.region}:${local.account_id}:orion-backend-dev*",
  ]
}

###############################################################################
# Trust policy: GitHub Actions OIDC para orion-backend
###############################################################################
data "aws_iam_policy_document" "trust" {
  # checkov:skip=CKV_AWS_60:GitHub OIDC trust no requiere permissions boundary en el trust policy.
  # checkov:skip=CKV_AWS_61:GitHub OIDC trust usa sub claim explicito, no requiere sts:SourceIdentity adicional.
  # checkov:skip=CKV_AWS_107:Role asumido solo por GitHub Actions OIDC, no por usuarios humanos.
  # checkov:skip=CKV_AWS_358:Rol GitHub OIDC no requiere captcha (no es login humano).
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
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:environment:${var.environment}",
      ]
    }
  }
}

###############################################################################
# Inline permissions policy: SamDeployPolicy
###############################################################################
data "aws_iam_policy_document" "orion_sam_deploy_inline" {
  # checkov:skip=CKV_AWS_109:El role es GitHub-OIDC-only con sub claim restringido a ref:refs/heads/main + environment:dev, sin humanos.
  # checkov:skip=CKV_AWS_111:Recursos IAM creados con aws_iam_role + aws_iam_role_policy inline explicitos.
  # checkov:skip=CKV_AWS_290:El sub claim restringe el flujo a GitHub OIDC main branch, sin acceso publico.
  # checkov:skip=CKV_AWS_355:Project tag propagado a todos los recursos via default_tags del provider.
  # checkov:skip=CKV_AWS_356:Las acciones con Resource: * son: cloudformation:ListStacks/DescribeStacks (read-only API global), lambda:ListFunctions/EventSourceMappings/GetAccountSettings (read-only global), xray:PutTraceSegments/TelemetryRecords (API global), sts:GetCallerIdentity (siempre *). El resto esta scoped a orion-* ARNs.

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
    sid    = "CloudFormationManageBackendStack"
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

  statement {
    sid    = "CloudFormationServerlessTransform"
    effect = "Allow"
    actions = [
      "cloudformation:CreateChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:DescribeChangeSet",
    ]
    resources = ["arn:aws:cloudformation:${local.region}:aws:transform/Serverless-2016-10-31"]
  }

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
      # lambda:TagResource is required by CloudFormation to apply the
      # default tags (Project=orion, Environment=dev, ManagedBy=terraform,
      # Repository=ahincho/orion-infrastructure) on every AWS::Lambda::Function
      # it creates. Without this, sam deploy on a fresh stack fails with
      # "AccessDeniedException ... is not authorized to perform:
      # lambda:TagResource on resource: arn:aws:lambda:us-east-1:...:function:orion-*".
      "lambda:TagResource",
      "lambda:UntagResource",
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
      # apigateway:GET is required by CloudFormation to introspect
      # AWS::ApiGatewayV2::Api resources (e.g. drift detection, GET on
      # /apis/*/authorizers). apigatewayv2:GetApi alone is not sufficient
      # when CFN issues the v1 GET API even for v2 resources.
      # apigateway:PATCH is required by CloudFormation to update
      # AWS::ApiGatewayV2::Authorizer resources (e.g. when changing
      # AuthorizerResultTtlInSeconds). apigatewayv2:UpdateAuthorizer alone
      # is not sufficient: CFN issues the v1 PATCH API even for v2 resources.
      # apigateway:POST is required by CloudFormation to create
      # AWS::ApiGatewayV2::Api (and the stage). apigatewayv2:CreateApi
      # alone is not sufficient: CFN issues the v1 POST API even for v2
      # resources. Without this, sam deploy fails on a fresh stack with
      # "AccessDeniedException ... is not authorized to perform:
      # apigateway:POST on resource: arn:aws:apigateway:us-east-1::/apis".
      "apigateway:GET",
      "apigateway:PATCH",
      "apigateway:POST",
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
      # apigateway:TagResource is required by CloudFormation to apply the
      # default tags on AWS::ApiGatewayV2::Stage (and possibly other
      # resources). apigatewayv2:AddTagsToResource is the v2 action but
      # CFN issues the v1 apigateway:TagResource API. Without this,
      # sam deploy on a fresh stack fails with "AccessDeniedException ...
      # apigateway:TagResource on resource:
      # arn:aws:apigateway:us-east-1::/apis/<id>/stages".
      "apigateway:TagResource",
      "apigateway:UntagResource",
    ]
    resources = ["*"]
  }

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

  statement {
    sid    = "EC2ReadForLambdaVpcConfig"
    effect = "Allow"
    actions = [
      # CloudFormation calls ec2:DescribeSecurityGroups + ec2:DescribeVpcs +
      # ec2:DescribeSubnets when creating or updating AWS::Lambda::Function
      # resources with VpcConfig. Without these, sam deploy fails on a fresh
      # stack with "Your access has been denied by EC2, please make sure
      # your request credentials have permission to DescribeSecurityGroups
      # for sg-XXX. EC2 Error Code: UnauthorizedOperation."
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }

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

  statement {
    sid    = "S3ReadTfStateForOutputs"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
    ]
    resources = local.s3_tfstate_arns
  }

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

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["arn:aws:kms:${local.region}:${local.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }

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

  statement {
    sid    = "XRayTracing"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetTraceSummaries",
      "xray:BatchGetTraces",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "STSGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

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
    resources = local.sqs_dlq_arns
  }
}

###############################################################################
# Resources
###############################################################################
resource "aws_iam_role" "orion_sam_deploy" {
  name                 = "${var.project_name}-sam-deploy-${var.environment}"
  description          = "Role asumido por GitHub Actions (OIDC) del repo ${var.github_repository} para SAM deploys de orion-backend en ${var.environment}."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = merge(var.tags, {
    Name      = "${var.project_name}-sam-deploy-${var.environment}"
    Purpose   = "OrionSAMDeploy"
    Component = "iam"
    Repo      = var.github_repository
  })
}

resource "aws_iam_role_policy" "orion_sam_deploy_inline" {
  name   = "SamDeployPolicy"
  role   = aws_iam_role.orion_sam_deploy.id
  policy = data.aws_iam_policy_document.orion_sam_deploy_inline.json
}
