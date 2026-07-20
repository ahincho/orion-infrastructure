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
#   9. modules/iam-sam-deploy-dev  IAM role + SamDeployPolicy para el
#                                  workflow `CD - Deploy` de orion-backend
#                                  (Phase 1.5 - bootstrap Terraform-managed)
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
  db_secret_arn       = module.rds_postgres.master_user_secret_arn
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
# Phase 1.5: SAM deploy role (orion-backend CD pipeline)
# -----------------------------------------------------------------------------
# Reemplaza el bootstrap manual previo (scripts/create-sam-deploy-role.sh).
# El role es asumido por el workflow `CD - Deploy` de orion-backend via
# GitHub OIDC (audience=sts.amazonaws.com, sub restringido a
# repo:ahincho/orion-backend:ref:refs/heads/main*environment:dev).
#
# Outputs:
#   - module.iam_sam_deploy_dev.role_arn -> set as AWS_DEPLOY_ROLE_ARN
#     en el GH Environment `dev` de orion-backend.
###############################################################################
module "iam_sam_deploy_dev" {
  source = "../../modules/iam-sam-deploy-dev"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  account_id   = local.account_id

  github_org          = "ahincho"
  github_repo         = "orion-backend"
  github_branch       = "refs/heads/main"
  github_environments = ["dev"]

  s3_artifacts_bucket = "orion-sam-artifacts-dev"

  tags = local.common_tags
}
