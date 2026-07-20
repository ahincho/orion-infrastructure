output "role_arn" {
  description = "ARN of the SAM deploy role. Set as AWS_DEPLOY_ROLE_ARN in the orion-backend GH Environment `dev` secret."
  value       = aws_iam_role.sam_deploy.arn
}

output "role_name" {
  description = "Name of the SAM deploy role (for `aws iam get-role-policy` lookups)."
  value       = aws_iam_role.sam_deploy.name
}

output "role_id" {
  description = "Stable IAM role ID (for cross-module references if needed)."
  value       = aws_iam_role.sam_deploy.id
}

output "policy_name" {
  description = "Name of the inline policy attached to the role."
  value       = aws_iam_role_policy.sam_deploy_inline.name
}
