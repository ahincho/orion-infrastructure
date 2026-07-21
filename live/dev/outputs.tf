###############################################################################
# Phase 0 outputs (smoke test + state infrastructure)
###############################################################################
output "state_bucket_name" {
  description = "Nombre del bucket S3 donde vive el state de Terraform."
  value       = module.storage_tfstate.bucket_id
}

output "oidc_provider_arn" {
  description = "ARN del IAM OIDC provider creado para GitHub Actions."
  value       = module.oidc_github.oidc_provider_arn
}

output "terraform_plan_role_arn" {
  description = "ARN del role IAM para terraform plan. Wire a GitHub Secret AWS_PLAN_ROLE_ARN."
  value       = module.oidc_github.terraform_plan_role_arn
}

output "terraform_apply_role_arn" {
  description = "ARN del role IAM para terraform apply. Wire a GitHub Secret AWS_APPLY_ROLE_ARN."
  value       = module.oidc_github.terraform_apply_role_arn
}

output "smoke_test" {
  description = "Smoke test para validar que el apply CD corrió efectivamente contra AWS."
  value = {
    account_id = data.aws_caller_identity.current.account_id
    arn        = data.aws_caller_identity.current.arn
    user_id    = data.aws_caller_identity.current.user_id
  }
}

###############################################################################
# Phase 1 outputs: Network
###############################################################################
output "vpc_id" {
  description = "ID del VPC principal ORION."
  value       = module.network.vpc_id
}

output "vpc_arn" {
  description = "ARN del VPC."
  value       = module.network.vpc_arn
}

output "vpc_cidr" {
  description = "CIDR block del VPC."
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs de subnets publicas (1 por AZ)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs de subnets privadas (1 por AZ)."
  value       = module.network.private_subnet_ids
}

output "vpc_endpoint_security_group_id" {
  description = "ID del SG aplicado a los Interface VPC endpoints."
  value       = module.network.vpc_endpoint_security_group_id
}

###############################################################################
# Phase 1 outputs: Data plane (RDS)
###############################################################################
output "rds_endpoint" {
  description = "Endpoint DNS del RDS Postgres (host:port)."
  value       = module.rds_postgres.endpoint
}

output "rds_hostname" {
  description = "Hostname del RDS."
  value       = module.rds_postgres.hostname
}

output "rds_port" {
  description = "Puerto del RDS (5432)."
  value       = module.rds_postgres.port
}

output "rds_database_name" {
  description = "Nombre de la DB inicial (default 'orion')."
  value       = module.rds_postgres.database_name
}

output "rds_master_username" {
  description = "Master username (default 'orion_admin'). Password en Secrets Manager (master_user_secret_arn)."
  value       = module.rds_postgres.master_username
}

output "rds_master_secret_arn" {
  description = "ARN del Secrets Manager secret con la master password (gestionado por RDS via manage_master_user_password). NO lo consume orion-backend (usa el app_connection_secret_arn)."
  value       = module.rds_postgres.master_user_secret_arn
}

output "rds_app_connection_secret_arn" {
  description = "ARN del secreto de aplicacion que orion-backend consume via SSM /orion/db/secret-arn. Contiene {host, port, database, username, password}."
  value       = module.rds_postgres.app_connection_secret_arn
}

output "rds_security_group_id" {
  description = "ID del SG del RDS."
  value       = module.rds_postgres.security_group_id
}

output "rds_db_subnet_group_name" {
  description = "Nombre del DB subnet group."
  value       = module.rds_postgres.db_subnet_group_name
}

###############################################################################
# Phase 1 outputs: Async plane (EventBridge)
###############################################################################
output "event_bus_name" {
  description = "Nombre del bus EventBridge custom (default orion-events-dev)."
  value       = module.eventbridge_bus.bus_name
}

output "event_bus_arn" {
  description = "ARN del bus EventBridge."
  value       = module.eventbridge_bus.bus_arn
}

output "event_log_group_name" {
  description = "CW Log Group que captura los eventos (observabilidad default)."
  value       = module.eventbridge_bus.event_log_group_name
}

###############################################################################
# Phase 1 outputs: Secrets (JWT)
###############################################################################
output "jwt_signing_secret_arn" {
  description = "ARN del Secrets Manager secret con el JWT HS256 signing key."
  value       = module.secrets_bootstrap.jwt_signing_secret_arn
}

output "jwt_signing_secret_name" {
  description = "Nombre (sin ARN) del secret JWT."
  value       = module.secrets_bootstrap.jwt_signing_secret_name
}

###############################################################################
# Phase 1 outputs: Lambda execution role + SG
###############################################################################
output "lambda_exec_role_arn" {
  description = "ARN del IAM execution role para las Lambdas orion-backend. Usar como 'Role' en SAM Functions."
  value       = module.iam_lambda_exec.role_arn
}

output "lambda_exec_role_name" {
  description = "Nombre del IAM execution role."
  value       = module.iam_lambda_exec.role_name
}

output "lambda_security_group_id" {
  description = "ID del SG dedicado para las Lambdas (referenciar desde template.yaml VpcConfig.SecurityGroupIds)."
  value       = module.iam_lambda_exec.lambda_security_group_id
}

###############################################################################
# Phase 1.7 outputs: SAM deploy role
# -----------------------------------------------------------------------------
# ARN del rol IAM que el workflow `CD - Deploy` de orion-backend asume via
# GitHub OIDC para correr `sam build` y `sam deploy`. Wire al GitHub
# Environment secret `AWS_DEPLOY_ROLE_ARN` (orion-backend / env: dev).
# Reemplaza al rol legacy `spark-match-sam-deploy-dev`.
###############################################################################
output "orion_sam_deploy_role_arn" {
  description = "ARN del IAM role orion-sam-deploy-dev (asumido por el CD - Deploy workflow de orion-backend). Wire a GitHub Environment secret AWS_DEPLOY_ROLE_ARN."
  value       = module.iam_sam_deploy_dev.role_arn
}

output "orion_sam_deploy_role_name" {
  description = "Nombre (sin ARN) del IAM role orion-sam-deploy-dev."
  value       = module.iam_sam_deploy_dev.role_name
}

###############################################################################
# Phase 1 outputs: SSM parameter paths (que orion-backend resuelve via {{resolve:ssm:...}})
###############################################################################
output "ssm_jwt_secret_arn_param" {
  description = "Path SSM del JWT secret ARN."
  value       = module.ssm_bootstrap.jwt_secret_arn_ssm_param_name
}

output "ssm_db_secret_arn_param" {
  description = "Path SSM del RDS master secret ARN."
  value       = module.ssm_bootstrap.db_secret_arn_ssm_param_name
}

output "ssm_event_bus_arn_param" {
  description = "Path SSM del EventBridge bus ARN."
  value       = module.ssm_bootstrap.eventbridge_bus_arn_ssm_param_name
}

output "ssm_cors_origins_param" {
  description = "Path SSM del CORS origins whitelist (JSON list)."
  value       = module.ssm_bootstrap.cors_allowed_origins_ssm_param_name
}

output "ssm_cors_origins_value" {
  description = "Valor actual del CORS origins whitelist (JSON-encoded list)."
  value       = module.ssm_bootstrap.cors_allowed_origins_value
  sensitive   = true
}

###############################################################################
# Phase 1.6 outputs: OrionAgentCore infra (Bedrock AgentCore)
# -----------------------------------------------------------------------------
# Consumidos por orion-cognitive-agent via SSM (futuro) o como GitHub Secrets
# del repo de deploy (inmediato).
###############################################################################

output "orion_agent_core_deploy_role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC del repo orion-cognitive-agent para deploys del agent. Wire a GitHub Secret AGENT_DEPLOY_ROLE_ARN."
  value       = module.iam_orion_agent_core_deploy.deploy_role_arn
}

output "orion_agent_core_deploy_role_name" {
  description = "Nombre (sin ARN) del IAM deploy role."
  value       = module.iam_orion_agent_core_deploy.deploy_role_name
}

output "orion_agent_core_ecr_repository_uri" {
  description = "Registry URL del ECR repository del agent (e.g. '681526276858.dkr.ecr.us-east-1.amazonaws.com/orion-agent-core-dev'). Usar en comandos docker push del pipeline."
  value       = module.ecr_orion_agent_core.repository_url
}

output "orion_agent_core_ecr_repository_arn" {
  description = "ARN del ECR repository del agent."
  value       = module.ecr_orion_agent_core.repository_arn
}

output "orion_agent_core_ecr_repository_name" {
  description = "Nombre (sin ARN, sin registry URL) del ECR repository del agent."
  value       = module.ecr_orion_agent_core.repository_name
}

output "orion_agent_core_runtime_role_arn" {
  description = "ARN del IAM role assumido por el contenedor dentro del Bedrock AgentCore Runtime. Wire como role_arn en el modulo bedrock-agent-core-runtime (PR #45). Anadirlo a AGENT_DEPLOY_ROLE_ARN no aplica (es el role de runtime, no el de deploy)."
  value       = module.iam_orion_agent_core_runtime.runtime_role_arn
}

output "orion_agent_core_runtime_role_name" {
  description = "Nombre (sin ARN) del IAM runtime execution role."
  value       = module.iam_orion_agent_core_runtime.runtime_role_name
}

output "orion_agent_core_runtime_id" {
  description = "ID del Bedrock AgentCore Runtime."
  value       = module.bedrock_agent_core_runtime.agent_runtime_id
}

output "orion_agent_core_runtime_arn" {
  description = "ARN del Bedrock AgentCore Runtime. Tras el primer `terraform apply`, copiar este valor al param `runtime_arn` del modulo `iam-orion-agent-core-runtime` (PR #44 2-fases bootstrap, fase 2) para tightens la trust policy con aws:SourceArn."
  value       = module.bedrock_agent_core_runtime.agent_runtime_arn
}

output "orion_agent_core_runtime_version" {
  description = "Version del Runtime (autoincrementa con cada Update). Se puede referenciar en el workflow de deploy para rolling update."
  value       = module.bedrock_agent_core_runtime.agent_runtime_version
}

output "orion_agent_core_runtime_endpoint_arn" {
  description = "ARN del Endpoint (alias). URL SigV4: https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/<endpoint_arn>/invocations."
  value       = module.bedrock_agent_core_runtime.endpoint_arn
}

output "orion_agent_core_runtime_endpoint_name" {
  description = "Nombre del Endpoint (alias)."
  value       = module.bedrock_agent_core_runtime.endpoint_name
}

###############################################################################
# Phase 2 outputs: Angular SPA hosting (orion-frontend)
# -----------------------------------------------------------------------------
# Consumidos por orion-frontend via GitHub Secrets / Variables:
#   - s3_bucket_name               -> GH Variable S3_BUCKET (repo-scoped)
#   - cloudfront_distribution_id   -> GH Variable CLOUDFRONT_DISTRIBUTION_ID (repo-scoped)
#   - cloudfront_domain_name       -> URL publica del SPA (referencia)
#   - spa_deploy_role_arn          -> GH Environment secret AWS_DEPLOY_ROLE_ARN (env=dev)
###############################################################################

output "s3_bucket_name" {
  description = "Nombre del bucket S3 del SPA Angular. Wire a GH Variable S3_BUCKET en orion-frontend."
  value       = module.cloudfront_spa_hosting.bucket_id
}

output "s3_bucket_arn" {
  description = "ARN del bucket S3 del SPA Angular."
  value       = module.cloudfront_spa_hosting.bucket_arn
}

output "cloudfront_distribution_id" {
  description = "ID del CloudFront distribution del SPA. Wire a GH Variable CLOUDFRONT_DISTRIBUTION_ID en orion-frontend."
  value       = module.cloudfront_spa_hosting.distribution_id
}

output "cloudfront_distribution_arn" {
  description = "ARN del CloudFront distribution del SPA."
  value       = module.cloudfront_spa_hosting.distribution_arn
}

output "cloudfront_domain_name" {
  description = "URL publica del SPA (e.g. 'd111111abcdef8.cloudfront.net')."
  value       = module.cloudfront_spa_hosting.distribution_domain_name
}

output "spa_deploy_role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC del repo orion-frontend para deploys del SPA. Wire a GH Environment secret AWS_DEPLOY_ROLE_ARN (env=dev)."
  value       = module.iam_angular_spa_deploy_dev.role_arn
}

output "spa_deploy_role_name" {
  description = "Nombre (sin ARN) del IAM role de deploy del SPA."
  value       = module.iam_angular_spa_deploy_dev.role_name
}
