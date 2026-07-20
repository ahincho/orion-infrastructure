output "runtime_role_arn" {
  description = "ARN del IAM role assumido por el contenedor dentro del Bedrock AgentCore Runtime. Wire como `role_arn` en el modulo `bedrock-agent-core-runtime` (PR #45)."
  value       = aws_iam_role.orion_agent_core_runtime.arn
}

output "runtime_role_name" {
  description = "Nombre (sin ARN) del IAM runtime execution role."
  value       = aws_iam_role.orion_agent_core_runtime.name
}

output "runtime_role_id" {
  description = "ID estable del IAM role (rol-unique)."
  value       = aws_iam_role.orion_agent_core_runtime.unique_id
}
