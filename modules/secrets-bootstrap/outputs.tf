output "jwt_signing_secret_arn" {
  description = "ARN del secret JWT signing en Secrets Manager. Usar como variable de entorno en los Lambdas del authorizer + identity."
  value       = aws_secretsmanager_secret.jwt_signing.arn
}

output "jwt_signing_secret_name" {
  description = "Nombre (sin ARN) del secret en Secrets Manager. Usar con `aws secretsmanager get-secret-value --secret-id <name>`."
  value       = aws_secretsmanager_secret.jwt_signing.name
}

output "jwt_signing_secret_id" {
  description = "ID del secret (incluye el sufijo random que AWS agrega al nombre)."
  value       = aws_secretsmanager_secret.jwt_signing.id
}

output "jwt_signing_initial_version_id" {
  description = "ID de la version inicial del secret. Util para tests de rotacion."
  value       = aws_secretsmanager_secret_version.jwt_signing_initial.version_id
}
