output "repository_name" {
  description = "Name of the ECR repository (e.g. `orion-agent`)."
  value       = aws_ecr_repository.agent.name
}

output "repository_arn" {
  description = "ARN of the ECR repository."
  value       = aws_ecr_repository.agent.arn
}

output "repository_uri" {
  description = "URI of the ECR repository (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`). Used by AgentCore Runtime as `container_uri`."
  value       = aws_ecr_repository.agent.repository_url
}

output "registry_id" {
  description = "AWS account ID that owns the ECR registry (matches `aws_ecr_repository.agent.registry_id`)."
  value       = aws_ecr_repository.agent.registry_id
}
