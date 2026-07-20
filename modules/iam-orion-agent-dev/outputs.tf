output "role_arn" {
  description = "ARN of the agent deploy role. Set as AWS_DEPLOY_ROLE_ARN in the orion-cognitive-agent GH Environment `dev` secret."
  value       = aws_iam_role.orion_agent_deploy.arn
}

output "role_name" {
  description = "Name of the agent deploy role (for `aws iam get-role-policy` lookups)."
  value       = aws_iam_role.orion_agent_deploy.name
}

output "role_id" {
  description = "Stable IAM role ID (for cross-module references if needed)."
  value       = aws_iam_role.orion_agent_deploy.id
}

output "policy_name" {
  description = "Name of the inline policy attached to the role."
  value       = aws_iam_role_policy.orion_agent_deploy_inline.name
}
