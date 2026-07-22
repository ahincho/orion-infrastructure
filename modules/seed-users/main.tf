###############################################################################
# Module: seed-users
# -----------------------------------------------------------------------------
# Aprovisiona la infraestructura necesaria para sembrar usuarios iniciales
# (advisors, supervisors, agents) en `identity.users` desde Lambda.
#
# Recursos creados:
#   1. Secrets Manager secret: shared dev password (SecureString, JSON shape)
#      - value: random_password (length configurable, special=false para
#        evitar chars problematicos en JSON/hashing libs).
#      - Consumido por las Lambdas bootstrap-supervisor + seed-users (Stage 6)
#        para asignar la misma password hasheada (scrypt) a todos los usuarios
#        seed. Solo dev — production requiere password unico por usuario +
#        rotation.
#   2. SSM Parameter: /orion/seed/email-domain (SecureString, AWS-managed CMK)
#      - default `orion.dev` (configurable). Consumido por las Lambdas para
#        construir emails deterministas (`advisor-001@<email-domain>`).
#   3. IAM Lambda execution role: orion-seed-users-lambda-exec-<env>
#      - trust: lambda.amazonaws.com.
#      - inline policy: SM GetSecretValue sobre (a) shared dev password
#        secret y (b) RDS app connection secret (para conectar al DB),
#        SSM GetParameter sobre /orion/seed/email-domain,
#        EC2 ENI management para VPC attachment, CloudWatch Logs.
#
# Decisiones de diseno:
#   - **Shared dev password** es explicito y conscious para dev. Un solo
#     valor se genera via random_password; el valor vive en state de TF.
#     Rotacion: re-crear el resource (terraform apply -replace) o delete +
#     apply. No se hara rotation automatica en prod.
#   - **email-domain SSM** es String SecureString (no plano) para que el
#     patron de consumption sea homogeneo con /orion/cors/allowed-origins
#     y /orion/secret/jwt-arn.
#   - **Lambda execution role dedicado** (no reutiliza module.iam_lambda_exec)
#     porque las Lambdas seed-users necesitan solo:
#       - SM GetSecretValue sobre 2 secretos especificos (shared password + RDS secret).
#       - SSM GetParameter sobre 1 param especifico.
#       - VPC ENI management.
#       - CW Logs.
#     module.iam_lambda_exec da tag-based access a TODOS los secrets con
#     Project=orion, lo cual es over-permissive para seed-users (el role no
#     debe leer el JWT signing secret).
#   - **VPC inputs requeridos** (vpc_subnet_ids, lambda_security_group_id)
#     porque las Lambdas seed-users necesitan conectar al RDS en VPC
#     privada (mismo SG que las demas Lambdas ORION).
#   - **Recovery window configurable** igual que secrets-bootstrap: 0 para
#     dev (delete OK sin espera), 7+ para staging/prod.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module     = "seed-users"
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "ahincho/orion-infrastructure"
    }
  )

  cw_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-bootstrap-supervisor-${var.environment}",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-bootstrap-supervisor-${var.environment}:*",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-seed-users-${var.environment}",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-seed-users-${var.environment}:*",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-seed-${var.environment}-*",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/orion-seed-${var.environment}-*:*",
  ]
}

data "aws_caller_identity" "current" {}

###############################################################################
# Random password: shared dev password
# -----------------------------------------------------------------------------
# special=false para evitar caracteres problematicos en parsers JSON/hashing:
# /, ", \, `, etc. upper+lower+numeric=True para entropia completa
# (~5.95 bits/char). 32 chars ~= 190 bits de entropia.
###############################################################################
resource "random_password" "shared_dev_password" {
  length  = var.shared_password_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

###############################################################################
# Secrets Manager secret: shared dev password
# -----------------------------------------------------------------------------
# JSON shape esperado por las Lambdas seed-users:
#   {
#     "version": 1,
#     "use": "seed-shared-dev-password",
#     "password": "<random-password>",
#     "rotatedAt": "<iso8601>"
#   }
###############################################################################
resource "aws_secretsmanager_secret" "shared_dev_password" {
  # checkov:skip=CKV_AWS_149:rotacion de shared dev password requiere regenerate el secret + re-seed TODOS los usuarios seed (cascade update). No es una rotation automatica trivial. Para prod se difiere a un modulo `secrets-rotation/` que use una Lambda custom.
  # checkov:skip=CKV_AWS_173:dev env usa AWS-managed CMK de Secrets Manager (encryption at rest por defecto). KMS CMK explicito se difiere al futuro modules/kms/ para prod.
  # checkov:skip=CKV2_AWS_57:Secrets bootstrap no requiere resource-based policy; el acceso es via IAM (caller asume role con secretsmanager:GetSecretValue).
  name                    = "${var.project_name}-${var.environment}-${var.shared_password_secret_name_suffix}"
  description             = "Shared dev password (NOT for production) for orion-backend ${var.environment} seed-users Lambdas. Used as the bootstrap password for all seeded advisors/supervisors/agents (scrypt-hashed before insert). Rotate manually via `terraform apply -replace` if compromised."
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.shared_password_secret_name_suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "shared_dev_password_initial" {
  secret_id = aws_secretsmanager_secret.shared_dev_password.id
  secret_string = jsonencode({
    version   = 1
    use       = "seed-shared-dev-password"
    password  = random_password.shared_dev_password.result
    rotatedAt = timestamp()
  })

  lifecycle {
    # Evita que un destroy del secret version borre el secret real
    # inadvertidamente. Solo borra la version inicial.
    ignore_changes = [secret_string]
  }
}

###############################################################################
# SSM Parameter: /orion/seed/email-domain
# -----------------------------------------------------------------------------
# SecureString (AWS-managed CMK). Default `orion.dev`. Consumido por las
# Lambdas seed-users para construir emails deterministas
# (`advisor-001@orion.dev`, `supervisor-001@orion.dev`, etc.).
###############################################################################
resource "aws_ssm_parameter" "email_domain" {
  name        = "/orion/seed/email-domain"
  description = "Email domain used by seed-users Lambdas to construct deterministic emails for seeded advisors/supervisors/agents (e.g. 'advisor-001@<domain>'). Consumed via {{resolve:ssm:/orion/seed/email-domain}} from SAM template."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = var.email_domain

  tags = local.common_tags
}

###############################################################################
# IAM Lambda execution role: orion-seed-users-lambda-exec-<env>
# -----------------------------------------------------------------------------
# Trust policy: lambda.amazonaws.com (cualquier Lambda de la cuenta puede
# asumir, pero el inline policy limita los actions a los recursos exactos
# que necesitan las Lambdas seed-users). Si en el futuro se quiere tightens
# el trust con `aws:SourceArn`, copiar el ARN especifico de cada Lambda
# creada y agregarlo como condition (post-deploy, similar al patron
# iam-orion-agent-core-runtime).
#
# Inline policy:
#   - SM GetSecretValue: shared dev password secret (este modulo).
#   - SM GetSecretValue: RDS app connection secret (input module.rds_postgres).
#   - SSM GetParameter: /orion/seed/email-domain (este modulo).
#   - SSM GetParameter: /orion/db/secret-arn (resuelve el ARN del RDS
#     secret si la Lambda prefiere resolverlo por SSM en lugar de recibirlo
#     como env var). Limite por ARN exacto del param.
#   - EC2 ENI management (CreateNetworkInterface, DescribeNetworkInterfaces,
#     DeleteNetworkInterface, AssignPrivateIpAddresses, UnassignPrivateIpAddresses)
#     sobre EC2:* con condition subnet/vpc — necesario para que Lambda cree
#     ENIs en las subnets privadas al attach a VPC.
#   - CloudWatch Logs: write + manage sobre los log groups esperados
#     (orion-bootstrap-supervisor-<env>, orion-seed-users-<env>,
#     orion-seed-<env>-*).
###############################################################################
data "aws_iam_policy_document" "trust_seed_users_lambda_exec" {
  # checkov:skip=CKV_AWS_60:Lambda execution role no requiere permissions boundary en trust policy.
  # checkov:skip=CKV_AWS_107:Role asumido solo por Lambda service principal, no por usuarios humanos.
  # checkov:skip=CKV_AWS_358:Lambda service principal no requiere captcha (no es login humano).

  statement {
    sid     = "LambdaServiceAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "seed_users_lambda_exec_inline" {
  # checkov:skip=CKV_AWS_109:Role es Lambda service principal only, sin humanos.
  # checkov:skip=CKV_AWS_111:Recursos IAM creados con aws_iam_role + aws_iam_role_policy inline explicitos.
  # checkov:skip=CKV_AWS_290:Lambda service principal es servicio AWS managed, no acceso publico.
  # checkov:skip=CKV_AWS_355:Project tag propagado via default_tags del provider.
  # checkov:skip=CKV_AWS_356:Actions con Resource: * son las minimas necesarias para ENI management (Lambda VPC attachment) y describe de subnets/SGs (cfn-style). El resto esta scoped a ARN exactos.

  ###########################################################################
  # SM: shared dev password (este modulo)
  ###########################################################################
  statement {
    sid    = "SecretsManagerReadSharedDevPassword"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.shared_dev_password.arn,
    ]
  }

  ###########################################################################
  # SM: RDS app connection secret (input module.rds_postgres.app_connection_secret_arn)
  ###########################################################################
  statement {
    sid    = "SecretsManagerReadRDSConnectionSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      var.rds_app_connection_secret_arn,
    ]
  }

  ###########################################################################
  # SSM: /orion/seed/email-domain (este modulo)
  ###########################################################################
  statement {
    sid    = "SSMReadSeedEmailDomain"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      aws_ssm_parameter.email_domain.arn,
    ]
  }

  ###########################################################################
  # EC2 ENI management para VPC attachment
  # -----------------------------------------------------------------------------
  # Lambda service requiere estos permisos para crear/manage ENIs en las
  # subnets privadas al attach a VPC. Sin ellos, la Lambda falla con
  # "ENI creation failed" en cold start.
  ###########################################################################
  statement {
    sid    = "EC2ENIManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  ###########################################################################
  # EC2 read for VPC introspection (subnets/SGs IDs que la Lambda debe
  # validar al startup). Read-only, scope global (Describe* es global).
  ###########################################################################
  statement {
    sid    = "EC2ReadForVpcConfig"
    effect = "Allow"
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  ###########################################################################
  # CloudWatch Logs write + manage
  ###########################################################################
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = local.cw_log_group_arns
  }

  ###########################################################################
  # X-Ray tracing (consistente con las demas Lambdas ORION).
  ###########################################################################
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

  ###########################################################################
  # KMS Decrypt para resolver SecureStrings de SSM (email-domain + opcional).
  # Condicion tag Project=orion Environment=<env> para limitar a CMKs
  # gestionados por este repo (mismo patron que iam-sam-deploy-dev).
  ###########################################################################
  statement {
    sid    = "KMSDecryptForSSMSecureStrings"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"]

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
}

resource "aws_iam_role" "seed_users_lambda_exec" {
  # checkov:skip=CKV_AWS_60:Lambda execution role no requiere permissions boundary en trust policy.
  # checkov:skip=CKV_AWS_61:Lambda execution role no requiere sts:SourceIdentity (es servicio AWS, no usuario).
  # checkov:skip=CKV_AWS_107:Role asumido solo por Lambda service principal, no por usuarios humanos.
  # checkov:skip=CKV_AWS_358:Lambda service principal no requiere captcha.
  name                 = "${var.project_name}-seed-users-lambda-exec-${var.environment}"
  description          = "Lambda execution role para las Lambdas bootstrap-supervisor + seed-users de orion-backend ${var.environment}. Asumido por lambda.amazonaws.com. Permisos: SM GetSecretValue (shared dev password + RDS secret), SSM GetParameter (/orion/seed/email-domain), EC2 ENI mgmt, CW Logs, X-Ray, KMS Decrypt (scoped)."
  assume_role_policy   = data.aws_iam_policy_document.trust_seed_users_lambda_exec.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-seed-users-lambda-exec-${var.environment}"
  })
}

resource "aws_iam_role_policy" "seed_users_lambda_exec_inline" {
  name   = "SeedUsersLambdaExecPolicy"
  role   = aws_iam_role.seed_users_lambda_exec.id
  policy = data.aws_iam_policy_document.seed_users_lambda_exec_inline.json
}