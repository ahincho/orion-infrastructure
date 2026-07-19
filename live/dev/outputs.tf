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