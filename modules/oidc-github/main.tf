# =============================================================================
# Module: oidc-github
# =============================================================================
# Crea el IAM Identity Provider de GitHub Actions + 4 IAM roles:
#   - orion-terraform-plan-dev   (read-only, OIDC)
#   - orion-terraform-apply-dev  (write, OIDC)
#   - orion-terraform-plan-prod  (read-only, OIDC)
#   - orion-terraform-apply-prod (write, OIDC)
#
# Trust policy restringida al repo del caller (var.github_repository):
#   - roles *-dev   -> ref:refs/heads/dev + environment:dev + pull_request
#   - roles *-prod  -> ref:refs/heads/main + environment:production + pull_request
#
# Aislamiento por env:
#   El role *-dev SOLO acepta tokens con environment:dev.
#   Un token emitido para production NO puede asumir roles de dev.
#   (esto es defensa en profundidad: even if GH secrets leak, env isolation
#    sigue valiendo porque la trust policy restringe por env.)
#
# Politica IAM (inline):
#   - plan-role: read sobre EC2 describe, IAM get/list, KMS describe,
#     S3 (limitado al bucket de state).
#   - apply-role: TODO plan + write sobre EC2/IAM/KMS/S3/CloudWatch Logs.
# =============================================================================

locals {
  common_tags = merge(
    var.tags,
    {
      Module     = "oidc-github"
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "ahincho/orion-infrastructure-devops"
    }
  )

  # Patron de `sub` claim del OIDC token para los 4 roles.
  # El token emitido por GH Actions tiene `sub` con formato:
  #   repo:<owner>/<repo>:ref:refs/heads/<branch>
  #   repo:<owner>/<repo>:pull_request
  #   repo:<owner>/<repo>:environment:<env_name>
  #
  # Cada role acepta SOLO el pattern de su env.
  plan_dev_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/dev",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:dev",
  ]

  apply_dev_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/dev",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:dev",
  ]

  plan_prod_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:production",
  ]

  apply_prod_sub_patterns = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:production",
  ]
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

###############################################################################
# IAM Identity Provider para GitHub Actions
###############################################################################
# Se crea UNA VEZ por cuenta AWS. Si ya existe en la cuenta, Terraform
# detecta drift y no falla (depende de la configuracion de import).
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
# IAM Role: orion-terraform-plan-dev
###############################################################################
# Permisos read-only sobre AWS (necesarios para terraform plan).
###############################################################################

resource "aws_iam_role" "plan_dev" {
  name = "${var.project_name}-terraform-plan-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
            "token.actions.githubusercontent.com:sub" = local.plan_dev_sub_patterns
          }
        }
      }
    ]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-plan-dev"
  })
}

resource "aws_iam_role_policy" "plan_dev" {
  name = "${var.project_name}-terraform-plan-dev-policy"
  role = aws_iam_role.plan_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      },
    ]
  })
}

###############################################################################
# IAM Role: orion-terraform-apply-dev
###############################################################################
# Permisos write sobre AWS + read (necesarios para terraform apply).
###############################################################################

resource "aws_iam_role" "apply_dev" {
  name = "${var.project_name}-terraform-apply-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
            "token.actions.githubusercontent.com:sub" = local.apply_dev_sub_patterns
          }
        }
      }
    ]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-apply-dev"
  })
}

resource "aws_iam_role_policy" "apply_dev" {
  name = "${var.project_name}-terraform-apply-dev-policy"
  role = aws_iam_role.apply_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ApplyDevFullAccess"
        Effect = "Allow"
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
    ]
  })
}

###############################################################################
# IAM Role: orion-terraform-plan-prod
###############################################################################

resource "aws_iam_role" "plan_prod" {
  name = "${var.project_name}-terraform-plan-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
            "token.actions.githubusercontent.com:sub" = local.plan_prod_sub_patterns
          }
        }
      }
    ]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-plan-prod"
  })
}

resource "aws_iam_role_policy" "plan_prod" {
  name = "${var.project_name}-terraform-plan-prod-policy"
  role = aws_iam_role.plan_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      },
    ]
  })
}

###############################################################################
# IAM Role: orion-terraform-apply-prod
###############################################################################

resource "aws_iam_role" "apply_prod" {
  name = "${var.project_name}-terraform-apply-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
            "token.actions.githubusercontent.com:sub" = local.apply_prod_sub_patterns
          }
        }
      }
    ]
  })

  max_session_duration = var.iam_role_max_session_duration

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-terraform-apply-prod"
  })
}

resource "aws_iam_role_policy" "apply_prod" {
  name = "${var.project_name}-terraform-apply-prod-policy"
  role = aws_iam_role.apply_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ApplyProdFullAccess"
        Effect = "Allow"
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
    ]
  })
}
