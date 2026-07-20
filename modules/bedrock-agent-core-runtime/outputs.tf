output "agent_runtime_id" {
  description = "ID del Bedrock AgentCore Runtime (opaco, formato AWS-managed). Usar para 'agent_runtime_id' de un aws_bedrockagentcore_agent_runtime_endpoint."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "agent_runtime_arn" {
  description = "ARN del Bedrock AgentCore Runtime. Una vez creado, copiar este valor al param runtime_arn del modulo iam-orion-agent-core-runtime (PR #44 2-fases bootstrap, fase 2) para tightens la trust policy con aws:SourceArn."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "agent_runtime_version" {
  description = "Version actual del Runtime. Cada UpdateAgentRuntime lo incrementa."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_version
}

output "endpoint_arn" {
  description = "ARN del Endpoint. URL de invocacion: https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/<endpoint_arn>/invocations (SigV4-signed)."
  value       = aws_bedrockagentcore_agent_runtime_endpoint.this.agent_runtime_endpoint_arn
}

output "endpoint_name" {
  description = "Nombre del endpoint (alias)."
  value       = aws_bedrockagentcore_agent_runtime_endpoint.this.name
}
