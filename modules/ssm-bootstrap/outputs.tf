output "jwt_secret_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del JWT secret. Null si jwt_secret_arn estaba vacio."
  value       = try(aws_ssm_parameter.jwt_secret_arn[0].name, null)
}

output "db_secret_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del RDS master secret. Null si db_secret_arn estaba vacio."
  value       = try(aws_ssm_parameter.db_secret_arn[0].name, null)
}

output "eventbridge_bus_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del bus EventBridge. Null si eventbridge_bus_arn estaba vacio."
  value       = try(aws_ssm_parameter.eventbridge_bus_arn[0].name, null)
}

output "cors_allowed_origins_ssm_param_name" {
  description = "Path del SSM param que contiene el JSON list de origins CORS."
  value       = aws_ssm_parameter.cors_allowed_origins.name
}

output "cors_allowed_origins_value" {
  description = "Valor actual del CORS allowed origins whitelist (JSON-encoded)."
  value       = aws_ssm_parameter.cors_allowed_origins.value
}

output "created_parameter_names" {
  description = "Lista de paths de SSM params efectivamente creados (util para wiring con policies IAM)."
  value = concat(
    try(aws_ssm_parameter.jwt_secret_arn[*].name, []),
    try(aws_ssm_parameter.db_secret_arn[*].name, []),
    try(aws_ssm_parameter.eventbridge_bus_arn[*].name, []),
    [aws_ssm_parameter.cors_allowed_origins.name],
  )
}
