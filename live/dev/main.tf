###############################################################################
# Phase 1 ORCHESTRATOR (live/dev/main.tf)
# -----------------------------------------------------------------------------
# Single AWS environment: dev. Push to main triggers terraform apply to dev
# (via spark-match-01-devops/terraform-apply.yml reusable workflow).
#
# Este main.tf reemplaza el smoke-test single-account setup y ahora orquesta
# los 6 modulos de Phase 1. Recursos que se crearan:
#
#   1. modules/storage-tfstate      S3 bucket para state remoto
#   2. modules/oidc-github         IAM OIDC provider + 2 IAM roles
#                                  (orion-terraform-plan, orion-terraform-apply)
#   3. modules/network             VPC + subnets + NAT + IGW + VPC endpoints
#                                  + flow logs (orion-dev-*)
#   4. modules/secrets-bootstrap   Secrets Manager JWT signing key (HS256)
#   5. modules/eventbridge-bus     custom bus orion-events-dev
#                                  + default observability rule + log group
#   6. modules/iam-lambda-exec     Lambda execution role + SG para las Lambdas
#                                  (VPC attachment + SM + SSM + EB + RDS auth)
#   7. modules/rds-postgres        RDS Postgres db.t4g.micro free-tier
#                                  (orion-dev-rds + orion_admin + orion DB)
#   8. modules/ssm-bootstrap       SSM params para wiring cross-ORION
#                                  (refs al bus + secret + CORS whitelist)
###############################################################################

###############################################################################
# Data sources
###############################################################################
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Pre-build SSM parameter full ARNs. Las Lambdas necesitan ssm:GetParameter
  # sobre estos ARN exactos (mismo path que crea ssm-bootstrap).
  # Esto evita el chicken-and-egg: iam-lambda-exec se crea ANTES de
  # ssm-bootstrap pero necesita las ARNs ya.
  ssm_parameter_arns = [
    for path in [
      "/orion/secret/jwt-arn",
      "/orion/db/secret-arn",
      "/orion/eventbridge/bus-arn",
      "/orion/cors/allowed-origins",
    ] : "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${path}"
  ]
}

###############################################################################
# Module: storage-tfstate (Phase 0)
###############################################################################
module "storage_tfstate" {
  source = "../../modules/storage-tfstate"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

###############################################################################
# Module: oidc-github (Phase 0)
###############################################################################
module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name      = var.project_name
  github_repository = var.github_repository
  tags              = local.common_tags
}

###############################################################################
# Phase 1: Network foundation
###############################################################################
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment

  single_nat_gateway = true # dev cost-saving (~32 USD/mes)

  # VPC endpoints interfaz cuestan ~$87/mes (6 endpoints x $0.01/h x 2 AZs).
  # Para free-tier, las Lambdas hablan a AWS APIs via NAT Gateway con
  # latencia ligeramente mayor pero zero-cost. Activar cuando se migre
  # a prod o cuando se quiera single-digit-ms latency to SM/SSM/ECR.
  enable_vpc_endpoints    = false
  flow_log_retention_days = 30

  tags = local.common_tags
}

###############################################################################
# Phase 1: Secrets Manager JWT signing key
###############################################################################
module "secrets_bootstrap" {
  source = "../../modules/secrets-bootstrap"

  project_name            = var.project_name
  environment             = var.environment
  recovery_window_in_days = 0 # dev: delete OK sin espera

  tags = local.common_tags
}

###############################################################################
# Phase 1: EventBridge custom bus (orion-events-dev)
###############################################################################
module "eventbridge_bus" {
  source = "../../modules/eventbridge-bus"

  project_name             = var.project_name
  environment              = var.environment
  enable_default_log_rule  = true
  event_log_retention_days = 30

  tags = local.common_tags
}

###############################################################################
# Phase 1: Lambda execution role + SG
###############################################################################
module "iam_lambda_exec" {
  source = "../../modules/iam-lambda-exec"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.network.vpc_id
  vpc_cidr = module.network.vpc_cidr

  # No secret_arns list: usa tag condition Project=orion en su lugar
  # (cycle-avoidance — el RDS master secret es creado por rds_postgres, no
  # podemos referenciarlo en iam_lambda_exec sin cycle).
  secretsmanager_tag_condition = true

  ssm_parameter_arns = local.ssm_parameter_arns

  eventbridge_bus_arn = module.eventbridge_bus.bus_arn

  # rds_db_resource_arn omitido: usar GetSecretValue-based auth en su lugar.
  # IAM database authentication se hara en un futuro modulo o via IAM identity
  # center (no incluido en Phase 1).

  tags = local.common_tags
}

###############################################################################
# Phase 1.7: SAM deploy role (orion-sam-deploy-dev)
# -----------------------------------------------------------------------------
# Reemplaza al rol legacy `spark-match-sam-deploy-dev` (parcheado a mano
# durante el bootstrap inicial) por uno Terraform-managed con naming orion-*
# y trust policy exclusiva al repo ahincho/orion-backend. El ARN se expone
# como output Terraform directo (`orion_sam_deploy_role_arn`) para wirearlo
# manualmente al GitHub Environment secret `AWS_DEPLOY_ROLE_ARN` (orion-backend
# / env: dev) tras el primer apply.
#
# Plan de migracion del rol legacy (post-merge):
#   1. terraform apply crea orion-sam-deploy-dev (nuevo).
#   2. Actualizar `AWS_DEPLOY_ROLE_ARN` (env: dev de orion-backend) al nuevo ARN.
#   3. Push vacio para validar CD - Deploy con el nuevo rol.
#   4. Si pasa: remover las entradas `repo:ahincho/orion-backend:*` del trust
#      policy de `spark-match-sam-deploy-dev` (deja solo las entradas del
#      repo spark-match-03-backend).
###############################################################################
module "iam_sam_deploy_dev" {
  source = "../../modules/iam-sam-deploy-dev"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  oidc_provider_arn = module.oidc_github.oidc_provider_arn
  github_repository = "ahincho/orion-backend"

  tags = local.common_tags
}

###############################################################################
# Phase 1: RDS Postgres (Free-tier compatible)
# -----------------------------------------------------------------------------
# Depende de: network.vpc_id, network.private_subnet_ids,
#             iam_lambda_exec.lambda_security_group_id (ingress allowlist 5432).
###############################################################################
module "rds_postgres" {
  source = "../../modules/rds-postgres"

  project_name = var.project_name
  environment  = var.environment

  engine_version    = "16.4"
  instance_class    = "db.t4g.micro" # free-tier eligible, ARM Graviton
  allocated_storage = 20             # free-tier max
  storage_type      = "gp3"

  # Network (de network module):
  vpc_id        = module.network.vpc_id
  db_subnet_ids = module.network.private_subnet_ids

  # Ingress allowlist: Lambdas ORION pueden conectar al DB port 5432.
  allowed_security_group_ids = [
    module.iam_lambda_exec.lambda_security_group_id,
  ]

  # Master user (password via manage_master_user_password=true -> Secrets Manager)
  master_username = "orion_admin"

  # Free-tier settings:
  multi_az                   = false
  deletion_protection        = false
  publicly_accessible        = false
  storage_encrypted          = true
  backup_retention_period    = 1
  auto_minor_version_upgrade = true

  tags = local.common_tags

  depends_on = [module.iam_lambda_exec]
}

###############################################################################
# Phase 1: SSM parameters cross-ORION (4 SSM SecureString params)
###############################################################################
module "ssm_bootstrap" {
  source = "../../modules/ssm-bootstrap"

  project_name = var.project_name
  environment  = var.environment

  # Cross-module wiring (los ARNs ya fueron creados por los otros modulos):
  jwt_secret_arn      = module.secrets_bootstrap.jwt_signing_secret_arn
  db_secret_arn       = module.rds_postgres.app_connection_secret_arn
  eventbridge_bus_arn = module.eventbridge_bus.bus_arn

  # CORS whitelist (default permite localhost:3000 + orion.dev).
  cors_allowed_origins = [
    "http://localhost:3000",
    "http://localhost:5173", # Vite dev server
    "https://orion.dev",
  ]

  # Lambda VPC config para orion-backend SAM deploy:
  # - lambda_subnet_ids: comma-separated list de subnet IDs privadas.
  # - lambda_security_group_id: SG ID de las Lambdas (modules/iam-lambda-exec).
  # orion-backend deploy.yml leera estos valores y los pasara al SAM
  # reusable workflow como parameter-overrides-json.
  lambda_subnet_ids        = module.network.private_subnet_ids
  lambda_security_group_id = module.iam_lambda_exec.lambda_security_group_id
  lambda_role_arn          = module.iam_lambda_exec.role_arn

  tags = local.common_tags
}

###############################################################################
# Phase 1.6: OrionAgentCore infra (Bedrock AgentCore Runtime deployment)
# -----------------------------------------------------------------------------
# - module.ecr_orion_agent_core: ECR repository privado para imagenes del agent.
# - module.iam_orion_agent_core_deploy: GitHub OIDC role asumido por
#   orion-cognitive-agent para deploys del agent (ECR pull + Bedrock AgentCore
#   control/data plane + Bedrock InvokeModel + CloudWatch logs + SSM read +
#   iam:PassRole hacia bedrock-agentcore.amazonaws.com).
# - module.iam_orion_agent_core_runtime: role asumido por el contenedor
#   dentro del AgentCore Runtime (PR #44). Permisos minimos: Bedrock
#   InvokeModel + CloudWatch logs sobre /aws/bedrock-agentcore/*.
# - module.bedrock_agent_core_runtime: aws_bedrockagentcore_agent_runtime
#   + aws_bedrockagentcore_agent_runtime_endpoint (este PR).
# - aws_ecr_repository_policy.orion_agent_core: otorga pull al deploy role +
#   al runtime role. Definido en live/dev (no en el modulo) para evitar cycle
#   entre los 4 modulos.
###############################################################################

module "ecr_orion_agent_core" {
  source = "../../modules/ecr-orion-agent-core"

  project_name = var.project_name
  environment  = var.environment

  image_tag_mutability = "MUTABLE" # dev only: permite retag + rollback
  scan_on_push         = true
  max_image_count      = 20

  # principal_arns_with_pull = [] # se aplica via aws_ecr_repository_policy abajo

  tags = local.common_tags
}

module "iam_orion_agent_core_deploy" {
  source = "../../modules/iam-orion-agent-core-deploy"

  project_name = var.project_name
  environment  = var.environment

  github_repository = "ahincho/orion-cognitive-agent"

  oidc_provider_arn  = module.oidc_github.oidc_provider_arn
  ecr_repository_arn = module.ecr_orion_agent_core.repository_arn

  # Permite al deploy job pasar el runtime execution role al servicio
  # bedrock-agentcore al crear/actualizar el AgentRuntime (PR #45).
  # El bloque dynamic "statement" del modulo solo se materializa si esta
  # lista tiene > 0 elementos.
  agentcore_runtime_role_arns = [
    module.iam_orion_agent_core_runtime.runtime_role_arn,
  ]

  tags = local.common_tags
}

# Modulo runtime execution role.
# Trust policy endurecida en 2 fases (ver AGENTS.md seccion "orion-cognitive-
# agent infra (Phase 1.6)"):
#   Fase 1 (PR #46): trust loose (solo service principal). Aplica lo que
#     crea el AgentRuntime y los modulos restantes. Sin condiciones.
#   Fase 2 (PR #50): tras el primer apply, copiar el output del AgentRuntime
#     ARN al param `runtime_arn` de este modulo y reaplicar. Esto actualiza
#     la assume_role_policy in-place (sin recreate role), agregando la
#     condition `aws:SourceArn` que restringe el assume SOLO al runtime
#     creado (defense in depth anti-confused-deputy).
module "iam_orion_agent_core_runtime" {
  source = "../../modules/iam-orion-agent-core-runtime"

  project_name = var.project_name
  environment  = var.environment

  # Fase 2 (post Apply 1): trust endurecido. Implementado via
  # `terraform_data` (post-apply `local-exec`) porque el wiring directo
  # `runtime_arn = module.bedrock_agent_core_runtime.agent_runtime_arn`
  # introduce un cycle en el graph:
  #   iam.runtime_arn <-> bedrock_agent_core_runtime.role_arn
  # El IAM module mantiene `runtime_arn = ""` (default) durante este
  # PR; el endurecimiento real ocurre en el `terraform_data` mas abajo
  # via `aws iam update-assume-role-policy` (idempotente, in-place).

  tags = local.common_tags
}

# Endurecimiento de la trust policy en 2 fases:
#   Fase 1 (PR #46): trust loose (cualquier Bedrock AgentCore puede
#                     assumir el role; util mientras el runtime no existe).
#   Fase 2 (este PR):  trust endurecido con `aws:SourceArn` igual al
#                     ARN del runtime concreto creado por Apply 1.
#
# El endurecimiento se implementa via `aws iam update-assume-role-policy`
# invocado desde un `terraform_data` con `local-exec`. Esto evita el
# cycle del Terraform graph (el modulo IAM mantenia sus inputs limpios)
# y aprovecha el AWS API nativo para update de trust policy in-place
# (sin recreate role).
#
# Pattern:
#   - `terraform_data` re-provisiona cuando `input` cambia.
#   - `input = module.bedrock_agent_core_runtime.agent_runtime_arn`
#     (referencia Terraform-graph valida; no hay cycle aqui porque
#     este data block no participa en el modulo IAM).
#   - El `local-exec` corre SOLO cuando el apply principal termina.
locals {
  runtime_arn_for_trust_policy = module.bedrock_agent_core_runtime.agent_runtime_arn
}

resource "terraform_data" "harden_runtime_trust_policy" {
  input = local.runtime_arn_for_trust_policy

  provisioner "local-exec" {
    # Force bash explicitly (the default on Windows is cmd.exe, which
    # does not support `set -euo pipefail`). On Linux runners (CI/CD)
    # and macOS dev environments, bash is at /bin/bash + PATH.
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      tmp="$(mktemp -t orion-trust.XXXXXX.json)"
      cat > "$$tmp" <<JSON
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Sid": "BedrockAgentCoreServiceAssume",
          "Effect": "Allow",
          "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
          "Action": "sts:AssumeRole",
          "Condition": {
            "StringEquals": {
              "aws:SourceArn": "${local.runtime_arn_for_trust_policy}"
            }
          }
        }]
      }
      JSON
      aws iam update-assume-role-policy \
        --role-name orion-agent-core-runtime-dev \
        --policy-document "file://$$tmp"
      rm -f "$$tmp"
    EOT
  }
}

# Bedrock AgentCore Runtime: el recurso aws_bedrockagentcore_agent_runtime +
# un aws_bedrockagentcore_agent_runtime_endpoint. Publica el contenedor en
# ECR + lo expone como endpoint invocable por SigV4.
module "bedrock_agent_core_runtime" {
  source = "../../modules/bedrock-agent-core-runtime"

  project_name = var.project_name
  environment  = var.environment

  container_uri = "${module.ecr_orion_agent_core.repository_url}:latest"
  role_arn      = module.iam_orion_agent_core_runtime.runtime_role_arn

  # Defaults del modulo: agent_runtime_name="orion_agent_core_dev",
  # endpoint_name="dev", network_mode="PUBLIC" (sin coste de VPC endpoints).

  # Env vars inyectadas al contenedor al arrancar. Tipicos:
  #   - AWS_REGION: provider ya lo inyecta, pero pasamos explicitamente
  #     para evitar confusion si la app lo lee antes que el SDK.
  #   - BEDROCK_MODEL_ID: el modelo que el agente invoca via Converse.
  #   - LOG_LEVEL: standard Python logging level.
  environment_variables = {
    AWS_REGION       = "us-east-1"
    BEDROCK_MODEL_ID = "us.anthropic.claude-sonnet-4-6" # Sonnet 4.6 (cross-region inference profile, ACTIVE, verificado en dev)
    LOG_LEVEL        = "INFO"
    ORION_AGENT_NAME = "OrionAgentCore"
    ORION_AGENT_ENV  = "dev"
  }

  tags = local.common_tags
}

# Cross-cycle resourceless wire: el deploy role + el runtime role necesitan
# pull del ECR repo. Se rompe el ciclo iam <-> ecr declarando el
# aws_ecr_repository_policy directamente en live/dev (fuera de cualquier modulo).
resource "aws_ecr_repository_policy" "orion_agent_core" {
  repository = module.ecr_orion_agent_core.repository_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullForOrionAgentCorePrincipals"
        Effect = "Allow"
        Principal = {
          AWS = [
            module.iam_orion_agent_core_deploy.deploy_role_arn,
            module.iam_orion_agent_core_runtime.runtime_role_arn,
          ]
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
