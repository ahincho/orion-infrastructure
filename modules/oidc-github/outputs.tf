output "oidc_provider_arn" {
  description = "ARN del IAM Identity Provider creado."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL del OIDC provider."
  value       = aws_iam_openid_connect_provider.github.url
}

output "terraform_plan_role_arn_dev" {
  description = "ARN del role plan-dev. Wire a GitHub Secret AWS_PLAN_ROLE_ARN_DEV."
  value       = aws_iam_role.plan_dev.arn
}

output "terraform_plan_role_arn_prod" {
  description = "ARN del role plan-prod. Wire a GitHub Secret AWS_PLAN_ROLE_ARN_PROD."
  value       = aws_iam_role.plan_prod.arn
}

output "terraform_apply_role_arn_dev" {
  description = "ARN del role apply-dev. Wire a GitHub Secret AWS_APPLY_ROLE_ARN_DEV."
  value       = aws_iam_role.apply_dev.arn
}

output "terraform_apply_role_arn_prod" {
  description = "ARN del role apply-prod. Wire a GitHub Secret AWS_APPLY_ROLE_ARN_PROD."
  value       = aws_iam_role.apply_prod.arn
}
