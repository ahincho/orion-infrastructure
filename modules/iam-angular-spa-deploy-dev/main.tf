###############################################################################
# Module: iam-angular-spa-deploy-dev
# -----------------------------------------------------------------------------
# Crea el IAM role + inline policy `AngularSpaDeployPolicy` que asume el
# workflow `CD - Deploy` de ahincho/orion-frontend via GitHub OIDC para
# hacer `aws s3 sync --delete` y `aws cloudfront create-invalidation`
# contra el bucket + distribution creados por modules/cloudfront-spa-hosting.
#
# Trust policy:
#   - Principal: token.actions.githubusercontent.com (OIDC).
#   - Condition: aud=sts.amazonaws.com, sub StringLike a
#     repo:ahincho/orion-frontend:ref:refs/heads/main + environment:dev.
#   - Solo el repo orion-frontend puede assumir; PRs de forks o spark-match
#     no son aceptados.
#
# AngularSpaDeployPolicy (inline):
#   - S3 read+write sobre el bucket del SPA (list + put + delete + get).
#     Scope por ARN pattern: <bucket_name> y <bucket_name>/*.
#   - CloudFront create-invalidation scoped al distribution especifico.
#   - STS:GetCallerIdentity (requerido por aws-actions/configure-aws-credentials).
#
# Decisiones:
#   - No managed policies adjuntas (todo inline en AngularSpaDeployPolicy).
#   - max_session_duration = 3600s (1h) default AWS.
#   - Permission scope estrictamente al bucket y distribution del SPA.
#     Si se quiere deploy a otro bucket/distribution en el futuro, anadir
#     nuevas statements; este modulo no se reusa para otros repos SPA sin
#     forkearlo.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region

  # S3 ARNs para el bucket del SPA. Scoped al bucket_name especifico
  # (pasado por el caller desde cloudfront-spa-hosting outputs).
  s3_bucket_arn  = "arn:aws:s3:::${var.bucket_name}"
  s3_object_arns = "${local.s3_bucket_arn}/*"

  # CloudFront distribution ARN para create-invalidation.
  cf_distribution_arn = "arn:aws:cloudfront::${local.account_id}:distribution/${var.cloudfront_distribution_id}"
}

###############################################################################
# Trust policy: GitHub Actions OIDC para orion-frontend
###############################################################################
data "aws_iam_policy_document" "trust" {
  # checkov:skip=CKV_AWS_60:GitHub OIDC trust no requiere permissions boundary.
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
# Inline permissions policy: AngularSpaDeployPolicy
###############################################################################
data "aws_iam_policy_document" "orion_spa_deploy_inline" {
  # checkov:skip=CKV_AWS_109:El role es GitHub-OIDC-only con sub claim restringido a ref:refs/heads/main + environment:dev, sin humanos.
  # checkov:skip=CKV_AWS_111:Recursos IAM creados con aws_iam_role + aws_iam_role_policy inline explicitos.
  # checkov:skip=CKV_AWS_290:El sub claim restringe el flujo a GitHub OIDC main branch, sin acceso publico.
  # checkov:skip=CKV_AWS_355:Project tag propagado a todos los recursos via default_tags del provider.

  statement {
    sid    = "S3ManageObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetEncryptionConfiguration",
    ]
    resources = [
      local.s3_bucket_arn,
      local.s3_object_arns,
    ]
  }

  statement {
    sid    = "CloudFrontInvalidateDistribution"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = [local.cf_distribution_arn]
  }

  statement {
    sid       = "STSGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

###############################################################################
# Resources
###############################################################################
resource "aws_iam_role" "orion_spa_deploy" {
  name                 = "${var.project_name}-angular-spa-deploy-${var.environment}"
  description          = "Role asumido por GitHub Actions (OIDC) del repo ${var.github_repository} para deploys del Angular SPA de orion-${var.environment} en S3+CloudFront."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = merge(var.tags, {
    Name      = "${var.project_name}-angular-spa-deploy-${var.environment}"
    Purpose   = "OrionAngularSPADeploy"
    Component = "iam"
    Repo      = var.github_repository
  })
}

resource "aws_iam_role_policy" "orion_spa_deploy_inline" {
  name   = "AngularSpaDeployPolicy"
  role   = aws_iam_role.orion_spa_deploy.id
  policy = data.aws_iam_policy_document.orion_spa_deploy_inline.json
}
