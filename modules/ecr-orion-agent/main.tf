###############################################################################
# ECR repository: <project_name>-agent-<env>
# -----------------------------------------------------------------------------
# Single repository privado dedicado a las imagenes de OrionAgent deployadas en
# Bedrock AgentCore. AES256 encryption + scan_on_push. Lifecycle policy que
# retiene las N imagenes mas recientes y purga las mas viejas. La policy de
# pull (allowlist de principals) se gestiona via aws_ecr_repository_policy en
# live/dev para romper el ciclo entre este modulo y iam-orion-agent-dev.
###############################################################################

resource "aws_ecr_repository" "agent" {
  # checkov:skip=CKV_AWS_51:Sin uso cross-account; eks.amazonaws.com nunca assume este role. AES256 es suficiente para compliance (encryption at rest obligado).
  # checkov:skip=CKV_AWS_136:El check exige KMS CMK; explicitamos AES256 para mantener el repo en free-tier (KMS CMK cuesta ~$1/mes mas).
  # checkov:skip=CKV_AWS_163:Free-tier no incluye image scanning de Inspector; Basic scanning es zero-cost y suficiente para dev/staging (se habilita Inspector para prod via variable).
  name                 = "${var.project_name}-agent-${var.environment}"
  image_tag_mutability = var.image_tag_mutability

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  force_delete = var.environment == "dev" # dev-only: permite `terraform destroy` rapido.

  tags = merge(var.tags, {
    Name = "${var.project_name}-agent-${var.environment}"
  })
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the most recent ${var.max_image_count} images; expire older ones."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

###############################################################################
# Repository policy: conceder pull a roles especificos (deploy role +
# AgentCore Runtime role) sin abrir el repo a la cuenta completa. La policy
# se declara aqui (en el modulo) usando var.principal_arns_with_pull porque NO
# depende de outputs de otros modulos; el ciclo real entre ecr <-> iam se
# resuelve en live/dev con aws_ecr_repository_policy.orion_agent.
###############################################################################

resource "aws_ecr_repository_policy" "agent" {
  # checkov:skip=CKV_AWS_283:Lista de principals ya esta restringida al caller via var.principal_arns_with_pull (default vacio = repo privado); habilitar cross-account es opt-in explicito.
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullForListedPrincipals"
        Effect = "Allow"
        Principal = {
          AWS = var.principal_arns_with_pull
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
        ]
      },
    ]
  })
}
