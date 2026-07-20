output "role_arn" {
  description = "ARN de la Lambda execution role. Usar como 'Role' en AWS::Lambda::Function (SAM template) o en template.yaml."
  value       = aws_iam_role.lambda_exec.arn
}

output "role_name" {
  description = "Nombre de la Lambda execution role."
  value       = aws_iam_role.lambda_exec.name
}

output "role_unique_id" {
  description = "Unique ID de la role (estable a traves de recreaciones con mismo name)."
  value       = aws_iam_role.lambda_exec.unique_id
}

output "lambda_security_group_id" {
  description = "ID del SG dedicado de las Lambdas. Referenciar desde modules/rds-postgres (allowed_security_group_ids) y API Gateway authorizer."
  value       = aws_security_group.lambda.id
}

output "managed_policies_attached" {
  description = "Lista de managed policy ARNs adjuntados (BasicExecutionRole, VPCAccessExecutionRole, TracingExecutionRole)."
  value = [
    aws_iam_role_policy_attachment.basic_execution.policy_arn,
    aws_iam_role_policy_attachment.vpc_execution.policy_arn,
    aws_iam_role_policy_attachment.xray_execution.policy_arn,
  ]
}

output "inline_policy_name" {
  description = "Nombre del inline policy (Secrets+SSM+EB+RDS). Null si ninguna input list/output estaba populated."
  value       = try(aws_iam_role_policy.inline[0].name, null)
}
