output "role_arn" {
  description = "ARN del IAM role. Usar como AuthorizerCredentialsArn en AWS::ApiGatewayV2::Authorizer de orion-backend template.yaml."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nombre del IAM role (con el sufijo aleatorio de name_prefix)."
  value       = aws_iam_role.this.name
}

output "role_unique_id" {
  description = "Unique ID del role (estable a traves de recreaciones con mismo name)."
  value       = aws_iam_role.this.unique_id
}
