output "deploy_role_arn" {
  description = "ARN del IAM role asumible por GitHub Actions OIDC para deploys de OrionAgentCore. Wire a GitHub Secret AGENT_DEPLOY_ROLE_ARN (orion-cognitive-agent)."
  value       = aws_iam_role.orion_agent_core_deploy.arn
}

output "deploy_role_name" {
  description = "Nombre (sin ARN) del IAM role de deploy."
  value       = aws_iam_role.orion_agent_core_deploy.name
}

output "deploy_role_id" {
  description = "ID estable del IAM role (rol-unique)."
  value       = aws_iam_role.orion_agent_core_deploy.unique_id
}
