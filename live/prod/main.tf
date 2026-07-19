# =============================================================================
# Phase 0 (closed): S3 state bucket + IAM OIDC roles + 4 terraform IAM roles.
# =============================================================================
# Mismo contenido que live/dev/main.tf. La diferencia esta en los
# var.* (env=prod, aws_region) y en los workflows reusables pinneados.
#
# Aplica via PR mergeado a main (GH Environment "production" requiere
# aprobacion manual de @ahincho).
# =============================================================================

module "storage_tfstate" {
  source = "../../modules/storage-tfstate"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name      = var.project_name
  aws_region        = var.aws_region
  github_repository = var.github_repository
}
