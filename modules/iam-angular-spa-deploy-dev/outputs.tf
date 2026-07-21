output "role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC para deploys del SPA. Wire a GitHub Environment secret AWS_DEPLOY_ROLE_ARN (orion-frontend / env: dev)."
  value       = aws_iam_role.orion_spa_deploy.arn
}

output "role_name" {
  description = "Nombre (sin ARN) del IAM role de deploy."
  value       = aws_iam_role.orion_spa_deploy.name
}

output "role_id" {
  description = "ID estable del IAM role (role-unique)."
  value       = aws_iam_role.orion_spa_deploy.unique_id
}
