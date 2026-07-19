# =============================================================================
# Phase 0: S3 state bucket + IAM OIDC provider + 2 IAM roles OIDC.
# =============================================================================
# Single AWS environment (dev). Push to main triggers apply to dev.
#
# Recursos que viven en AWS:
#   - orion-tfstate-dev (S3 bucket para state remoto)
#   - IAM OIDC provider para token.actions.githubusercontent.com
#   - 2 IAM roles asumidos desde GitHub Actions via OIDC:
#       * orion-terraform-plan   (read-only sobre AWS)
#       * orion-terraform-apply  (write sobre AWS)
# =============================================================================

###############################################################################
# Module: storage-tfstate
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
# Crea el IAM Identity Provider + 2 roles IAM:
#   - orion-terraform-plan   (assume role para terraform plan)
#   - orion-terraform-apply  (assume role para terraform apply)
#
# Trust policy restringida al repo de este caller (var.github_repository)
# y al GH Environment "dev".
###############################################################################
module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name      = var.project_name
  github_repository = var.github_repository
}