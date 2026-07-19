# -- State bucket --
output "state_bucket_id" {
  description = "Nombre del bucket S3 donde se almacena el state de este env."
  value       = module.storage_tfstate.bucket_id
}

output "state_bucket_arn" {
  description = "ARN del bucket S3 de state."
  value       = module.storage_tfstate.bucket_arn
}

output "state_bucket_region" {
  description = "Region donde vive el bucket de state."
  value       = module.storage_tfstate.bucket_region
}

# -- OIDC provider --
output "oidc_provider_arn" {
  description = "ARN del IAM Identity Provider de GitHub Actions."
  value       = module.oidc_github.oidc_provider_arn
}

# -- Terraform IAM roles --
output "terraform_plan_role_arn_dev" {
  description = "ARN del role OIDC para terraform plan en dev. Wire a GitHub Secret AWS_PLAN_ROLE_ARN_DEV."
  value       = module.oidc_github.terraform_plan_role_arn_dev
}

output "terraform_apply_role_arn_dev" {
  description = "ARN del role OIDC para terraform apply en dev. Wire a GitHub Secret AWS_APPLY_ROLE_ARN_DEV."
  value       = module.oidc_github.terraform_apply_role_arn_dev
}

output "terraform_plan_role_arn_prod" {
  description = "ARN del role OIDC para terraform plan en prod. Wire a GitHub Secret AWS_PLAN_ROLE_ARN_PROD."
  value       = module.oidc_github.terraform_plan_role_arn_prod
}

output "terraform_apply_role_arn_prod" {
  description = "ARN del role OIDC para terraform apply en prod. Wire a GitHub Secret AWS_APPLY_ROLE_ARN_PROD."
  value       = module.oidc_github.terraform_apply_role_arn_prod
}
