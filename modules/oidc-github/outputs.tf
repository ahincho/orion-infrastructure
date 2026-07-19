output "oidc_provider_arn" {
  description = "ARN del IAM Identity Provider creado."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL del OIDC provider."
  value       = aws_iam_openid_connect_provider.github.url
}

output "terraform_plan_role_arn" {
  description = "ARN del role plan. Wire a GitHub Secret AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "terraform_apply_role_arn" {
  description = "ARN del role apply. Wire a GitHub Secret AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.apply.arn
}