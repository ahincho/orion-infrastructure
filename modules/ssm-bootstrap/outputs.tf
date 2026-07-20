output "jwt_secret_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del JWT secret. Null si jwt_secret_arn estaba vacio."
  value       = try(aws_ssm_parameter.optional_arn["/orion/secret/jwt-arn"].name, null)
}

output "db_secret_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del RDS master secret. Null si db_secret_arn estaba vacio."
  value       = try(aws_ssm_parameter.optional_arn["/orion/db/secret-arn"].name, null)
}

output "eventbridge_bus_arn_ssm_param_name" {
  description = "Path del SSM param que contiene el ARN del bus EventBridge. Null si eventbridge_bus_arn estaba vacio."
  value       = try(aws_ssm_parameter.optional_arn["/orion/eventbridge/bus-arn"].name, null)
}

output "cors_allowed_origins_ssm_param_name" {
  description = "Path del SSM param que contiene el JSON list de origins CORS."
  value       = aws_ssm_parameter.cors_allowed_origins.name
}

output "cors_allowed_origins_value" {
  description = "Valor actual del CORS allowed origins whitelist (JSON-encoded)."
  value       = aws_ssm_parameter.cors_allowed_origins.value
}

output "lambda_vpc_subnet_ids_param_name" {
  description = "Path del SSM param con VPC subnet IDs (comma-separated). Null si no se proveyeron subnets."
  value       = try(aws_ssm_parameter.lambda_vpc_subnet_ids[0].name, null)
}

output "lambda_vpc_subnet_ids_value" {
  description = "Valor del SSM param con VPC subnet IDs (comma-separated)."
  value       = try(aws_ssm_parameter.lambda_vpc_subnet_ids[0].value, null)
}

output "lambda_security_group_id_param_name" {
  description = "Path del SSM param con Lambda SG ID. Null si no se proveyo SG."
  value       = try(aws_ssm_parameter.lambda_security_group_id[0].name, null)
}

output "lambda_security_group_id_value" {
  description = "Valor del SSM param con Lambda SG ID."
  value       = try(aws_ssm_parameter.lambda_security_group_id[0].value, null)
}

output "lambda_role_arn_param_name" {
  description = "Path del SSM param con Lambda role ARN. Null si no se proveyo role."
  value       = try(aws_ssm_parameter.lambda_role_arn[0].name, null)
}

output "created_parameter_names" {
  description = "Lista de paths de SSM params efectivamente creados (util para wiring con policies IAM)."
  value = concat(
    [for p in aws_ssm_parameter.optional_arn : p.name],
    [aws_ssm_parameter.cors_allowed_origins.name],
    [for p in aws_ssm_parameter.lambda_vpc_subnet_ids : p.name],
    [for p in aws_ssm_parameter.lambda_security_group_id : p.name],
    [for p in aws_ssm_parameter.lambda_role_arn : p.name],
  )
}
