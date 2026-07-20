output "role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC para SAM deploys de orion-backend. Wire a GitHub Environment secret AWS_DEPLOY_ROLE_ARN (orion-backend / env: dev)."
  value       = aws_iam_role.orion_sam_deploy.arn
}

output "role_name" {
  description = "Nombre (sin ARN) del IAM role de deploy."
  value       = aws_iam_role.orion_sam_deploy.name
}

output "role_id" {
  description = "ID estable del IAM role (role-unique)."
  value       = aws_iam_role.orion_sam_deploy.unique_id
}
