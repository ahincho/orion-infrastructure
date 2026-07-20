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
# Phase 1.6 outputs: Orion Agent infra (Bedrock AgentCore)
# -----------------------------------------------------------------------------
# Consumidos por orion-cognitive-agent via SSM (futuro) o como GitHub Secrets
# del repo de deploy (inmediato).
###############################################################################

output "orion_agent_deploy_role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC del repo orion-cognitive-agent para deploys del agent. Wire a GitHub Secret AGENT_DEPLOY_ROLE_ARN."
  value       = module.iam_orion_agent_dev.deploy_role_arn
}

output "orion_agent_deploy_role_name" {
  description = "Nombre (sin ARN) del IAM deploy role."
  value       = module.iam_orion_agent_dev.deploy_role_name
}

output "orion_agent_ecr_repository_uri" {
  description = "Registry URL del ECR repository del agent (e.g. '681526276858.dkr.ecr.us-east-1.amazonaws.com/orion-agent-dev'). Usar en comandos docker push del pipeline."
  value       = module.ecr_orion_agent.repository_url
}

output "orion_agent_ecr_repository_arn" {
  description = "ARN del ECR repository del agent."
  value       = module.ecr_orion_agent.repository_arn
}

output "orion_agent_ecr_repository_name" {
  description = "Nombre (sin ARN, sin registry URL) del ECR repository del agent."
  value       = module.ecr_orion_agent.repository_name
}
