output "repository_id" {
  description = "ID del ECR repository (registry URL sin tag, e.g. 'ecr_id')."
  value       = aws_ecr_repository.agent.id
}

output "repository_arn" {
  description = "ARN del ECR repository."
  value       = aws_ecr_repository.agent.arn
}

output "repository_name" {
  description = "Nombre del repository (e.g. 'orion-agent-dev')."
  value       = aws_ecr_repository.agent.name
}

output "repository_url" {
  description = "Registry URL completa del repo (e.g. '<account>.dkr.ecr.us-east-1.amazonaws.com/orion-agent-dev')."
  value       = aws_ecr_repository.agent.repository_url
}
