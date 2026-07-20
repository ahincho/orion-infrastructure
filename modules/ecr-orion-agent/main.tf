###############################################################################
# Module: ecr-orion-agent
# -----------------------------------------------------------------------------
# Crea el repositorio ECR (Elastic Container Registry) donde el workflow
# `CD - Deploy` de orion-cognitive-agent pushea la imagen Docker del agente.
# Esa imagen es luego consumida por Bedrock AgentCore Runtime
# (modules/bedrock-agentcore-runtime, Sprint B.2).
#
# Configuracion:
#   - image_tag_mutability = IMMUTABLE (recomendado AWS — previene
#     overwrite de tags en uso; essential para rollback seguro).
#   - image_scanning_configuration.scan_on_push = true (CVE scan automatic
#     al push — queda registrado en el Service).
#   - encryption_configuration.encryption_type = AES256 (SSE-S3).
#     KMS se omite para mantener cero-cost en dev (matching la estrategia
#     de modules/storage-tfstate).
#   - lifecycle_policy: max_image_count = 30 (cleanup automatico; 30
#     imagenes cubre ~ 1 mes de deploys diarios).
#
# Resource-based policy: permite al IAM role `orion-agent-deploy-dev`
# (creado por modules/iam-orion-agent-dev) pushear imagenes. El role
# ARN se pasa como variable (`deploy_role_arn`).
#
# checkov skips:
#   - CKV_AWS_51:  ECR tag immutability habilitado por debajo.
#   - CKV_AWS_136: SSE-S3 AES256 (no KMS) — single-region dev; KMS
#                  agrega costo sin beneficio medible para ECR de
#                  imagenes agent (matching storage-tfstate trade-off).
#   - CKV_AWS_163: scan_on_push = true habilitado por debajo.
#   - CKV_AWS_283: el RBP NO permite "ALL" ni "*" como actions; solo
#                  lista explicita de ecr: actions (ver mas abajo).
#   - CKV2_AWS_62: sin event notifications (no aplica para ECR de
#                  imagenes agent; nadie suscribe al push event).
###############################################################################

locals {
  repo_name = "${var.project_name}-agent"
  common_tags = merge(
    var.tags,
    {
      Module      = "ecr-orion-agent"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
      Purpose     = "ECR repo for orion-cognitive-agent Docker image"
    }
  )
}

###############################################################################
# ECR repository
###############################################################################
resource "aws_ecr_repository" "agent" {
  #checkov:skip=CKV_AWS_51:ECR uses image_tag_mutability = IMMUTABLE below
  #checkov:skip=CKV_AWS_136:SSE-S3 AES256 sufficient for dev; KMS adds cost without benefit
  #checkov:skip=CKV_AWS_163:image_scanning_configuration.scan_on_push = true below
  name                 = local.repo_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = local.repo_name
  })
}

###############################################################################
# Lifecycle policy: cap max image count (cleanup automatico)
###############################################################################
# Mantiene el repo acotado a var.max_image_count imagenes. Cuando el
# workflow empuja una imagen que supera el limite, AWS automaticamente
# borra las mas antiguas. Para dev, 30 covers ~1 mes de deploys diarios.
###############################################################################
resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep at most ${var.max_image_count} images, expire older"
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
# Resource-based policy: permitir push al IAM deploy role.
# -----------------------------------------------------------------------------
# Sin este policy, el role `orion-agent-deploy-dev` podria intentar
# `ecr:PutImage` pero IAM rechaza porque el recurso no esta en su
# statement. El RBP atacha los permisos directamente al repo.
# Pull no se incluye aqui porque AgentCore usa el IAM execution role
# (creado por el modulo de Runtime en Sprint B.2), no el deploy role.
###############################################################################
data "aws_iam_policy_document" "agent_repo_policy" {
  #checkov:skip=CKV_AWS_283:Actions list is explicit no ALL or * allowed
  statement {
    sid    = "AllowOrionAgentDeployPush"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.deploy_role_arn]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]

    resources = [
      aws_ecr_repository.agent.arn,
      "${aws_ecr_repository.agent.arn}/*",
    ]
  }
}

resource "aws_ecr_repository_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy     = data.aws_iam_policy_document.agent_repo_policy.json
}
