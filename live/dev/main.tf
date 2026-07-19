# =============================================================================
# Phase 0 (closed): S3 state bucket + IAM OIDC roles + 4 terraform IAM roles.
# =============================================================================
# Recursos que viven en AWS:
#   - orion-tfstate-dev (S3 bucket para state remoto de este env)
#   - IAM OIDC provider para token.actions.githubusercontent.com
#   - 4 IAM roles asumidos desde GitHub Actions via OIDC:
#       * orion-terraform-plan-dev   (read-only sobre AWS)
#       * orion-terraform-apply-dev  (write sobre AWS)
# =============================================================================
# Aplica via PR mergeado a dev (GH Environment "dev" sin reviewers, auto-approve).

###############################################################################
# Module: storage-tfstate
###############################################################################
# Crea el bucket S3 para almacenar el state de Terraform de ESTE entorno.
# Idempotente: si el bucket ya existe, no falla. La primera vez se crea via
# scripts/bootstrap-backend.sh (fuera de Terraform, chicken-and-egg).
#
# Decisiones:
#   - Versionado habilitado (obligatorio para state + lockfile).
#   - Encriptacion server-side AES256 (FIPS 140-2 compliant).
#   - Acceso publico bloqueado (4 flags).
#   - use_lockfile = true en versions.tf (Terraform >= 1.6, sin DynamoDB).
###############################################################################

module "storage_tfstate" {
  source = "../../modules/storage-tfstate"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

###############################################################################
# Module: oidc-github
###############################################################################
# Crea el IAM Identity Provider de GitHub Actions + 4 roles IAM:
#   - orion-terraform-plan-dev   (assume role para terraform plan)
#   - orion-terraform-apply-dev  (assume role para terraform apply)
#   - orion-terraform-plan-prod  (assume role para terraform plan)
#   - orion-terraform-apply-prod (assume role para terraform apply)
#
# Trust policy restringida al repo de este caller (var.github_repository).
# Cada role solo acepta `sub` claim matcheando su env:
#   - roles *-dev   -> ref:refs/heads/dev + environment:dev + pull_request
#   - roles *-prod  -> ref:refs/heads/main + environment:production + pull_request
#
# Los ARNs se exponen como outputs y se wirean a GitHub Secrets via gh CLI
# (ver docs/SETUP.md).
###############################################################################

module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name     = var.project_name
  aws_region       = var.aws_region
  github_repository = var.github_repository
}
