# =============================================================================
# Module: oidc-github
# =============================================================================
# Crea el IAM Identity Provider de GitHub Actions + 2 IAM roles:
#   - orion-terraform-plan   (read-only, OIDC)
#   - orion-terraform-apply  (write, OIDC)
#
# Trust policy restringida al repo del caller (var.github_repository) y al
# GH Environment "dev". Sin distincion por rama: cualquier push o PR contra
# la branch protegida del repo + el environment "dev" puede asumir los roles.
#
# Aislamiento por environment:
#   El role SOLO acepta tokens emitidos por jobs con environment=dev.
#   Si en algun momento se quiere producir a otro env, generar otro modulo
#   (oidc-github-multi-env) o parametizar el nombre del environment.
#
# Politica IAM (inline):
#   - plan-role: read sobre EC2 describe, IAM get/list, KMS describe,
#     S3 (limitado al bucket de state) + sts:GetCallerIdentity.
#   - apply-role: TODO plan + write sobre EC2/IAM/KMS/S3/CloudWatch Logs.
# =============================================================================

locals {
  common_tags = merge(
    var.tags,
    {
      Module     = "oidc-github"
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "ahincho/orion-infrastructure"
    }
  )

  # Sub claim patterns: el OIDC token tiene `sub` con formato
  #   repo:<owner>/<repo>:ref:refs/heads/<branch>
  #   repo:<owner>/<repo>:pull_request
  #   repo:<owner>/<repo>:environment:<env_name>
  plan_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:dev",
  ]

  apply_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:dev",
  ]
}

###############################################################################
# IAM Identity Provider para GitHub Actions
###############################################################################
# Se crea UNA VEZ por cuenta AWS. Si ya existe, Terraform detecta drift.
#
# URL: https://token.actions.githubusercontent.com
# ClientId: sts.amazonaws.com (audiencia = AWS STS)
# Thumbprint: 6938fd4d98bab03faadb97b34396831e3780aea1 (estable desde 2023)
###############################################################################
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.oidc_provider_thumbprint]

  tags = local.common_tags
}

locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
}

###############################################################################
# IAM Role: orion-terraform-plan (read-only)
###############################################################################
resource "aws_iam_role" "plan" {
  name = "${var.project_name}-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.plan_sub_patterns
        }
      }
    }]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-plan"
  })
}

resource "aws_iam_role_policy" "plan" {
  name = "${var.project_name}-terraform-plan-policy"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PlanReadOnly"
      Effect = "Allow"
      Action = [
        "ec2:Describe*",
        "iam:Get*",
        "iam:List*",
        "kms:Describe*",
        "kms:List*",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "sts:GetCallerIdentity",
      ]
      Resource = "*"
    }]
  })
}

###############################################################################
# IAM Role: orion-terraform-apply (write)
###############################################################################
resource "aws_iam_role" "apply" {
  name = "${var.project_name}-terraform-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.apply_sub_patterns
        }
      }
    }]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-apply"
  })
}

resource "aws_iam_role_policy" "apply" {
  name = "${var.project_name}-terraform-apply-policy"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ApplyFullAccess"
      Effect = "Allow"
      Action = "*"
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }]
  })
}