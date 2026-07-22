output "shared_dev_password_secret_arn" {
  description = "ARN del Secrets Manager secret con el shared dev password (JSON shape: {version, use, password, rotatedAt}). Consumido por las Lambdas bootstrap-supervisor + seed-users (Stage 6) via SM GetSecretValue."
  value       = aws_secretsmanager_secret.shared_dev_password.arn
}

output "shared_dev_password_secret_name" {
  description = "Nombre (sin ARN) del secret en Secrets Manager."
  value       = aws_secretsmanager_secret.shared_dev_password.name
}

output "shared_dev_password_secret_id" {
  description = "ID del secret (incluye el sufijo random que AWS agrega al nombre)."
  value       = aws_secretsmanager_secret.shared_dev_password.id
}

output "shared_dev_password_initial_version_id" {
  description = "ID de la version inicial del secret. Util para tests de rotacion."
  value       = aws_secretsmanager_secret_version.shared_dev_password_initial.version_id
}

output "email_domain_ssm_param_name" {
  description = "Path del SSM param que contiene el email domain para usuarios seed (/orion/seed/email-domain). Consumido por las Lambdas seed-users via {{resolve:ssm:/orion/seed/email-domain}} o ssm:GetParameter."
  value       = aws_ssm_parameter.email_domain.name
}

output "email_domain_ssm_param_arn" {
  description = "ARN del SSM param /orion/seed/email-domain."
  value       = aws_ssm_parameter.email_domain.arn
}

output "email_domain_value" {
  description = "Valor actual del email domain (referencia). NOTA: el valor es publico (orion.dev) y se expone para conveniencia en outputs Terraform. No contiene secretos."
  value       = aws_ssm_parameter.email_domain.value
}

output "lambda_exec_role_arn" {
  description = "ARN del IAM Lambda execution role (orion-seed-users-lambda-exec-<env>) para las Lambdas bootstrap-supervisor + seed-users. Wire a SAM Function.Role en template.yaml (Stage 6)."
  value       = aws_iam_role.seed_users_lambda_exec.arn
}

output "lambda_exec_role_name" {
  description = "Nombre (sin ARN) del IAM Lambda execution role."
  value       = aws_iam_role.seed_users_lambda_exec.name
}

output "lambda_exec_role_id" {
  description = "ID estable del IAM role (role-unique)."
  value       = aws_iam_role.seed_users_lambda_exec.unique_id
}

output "trust_policy" {
  description = "JSON de la trust policy final aplicada al Lambda execution role. Solo contiene el service principal lambda.amazonaws.com."
  value       = data.aws_iam_policy_document.trust_seed_users_lambda_exec.json
}