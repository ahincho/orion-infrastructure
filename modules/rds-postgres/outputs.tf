output "instance_id" {
  description = "ID de la instancia RDS (terraform-internal). Tambien disponible como 'resource_id'."
  value       = aws_db_instance.main.id
}

output "instance_arn" {
  description = "ARN de la instancia RDS."
  value       = aws_db_instance.main.arn
}

output "instance_resource_id" {
  description = "Resource ID (DbiResourceId) de la instancia. Util para metricas/logs en CW."
  value       = aws_db_instance.main.resource_id
}

output "endpoint" {
  description = "Endpoint DNS de la DB (host:port). Usar como DATABASE_URL en orion-backend."
  value       = aws_db_instance.main.endpoint
}

output "hostname" {
  description = "Solo el hostname (sin puerto)."
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Puerto TCP (5432 para Postgres)."
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Nombre de la DB inicial."
  value       = aws_db_instance.main.db_name
}

output "master_username" {
  description = "Master username configurado."
  value       = aws_db_instance.main.username
}

output "master_user_secret_arn" {
  description = "ARN del Secrets Manager secret con la master password (gestionado por RDS cuando manage_master_user_password=true)."
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}

output "app_connection_secret_arn" {
  description = "ARN del Secrets Manager secret de aplicacion (5 campos JSON: host, port, database, username, password). Es el que orion-backend consume via SSM /orion/db/secret-arn."
  value       = aws_secretsmanager_secret.app.arn
}

output "app_connection_secret_name" {
  description = "Nombre (sin ARN) del secreto de aplicacion."
  value       = aws_secretsmanager_secret.app.name
}

output "security_group_id" {
  description = "ID del SG dedicado de la DB."
  value       = aws_security_group.db.id
}

output "db_subnet_group_name" {
  description = "Nombre del DB subnet group (modules/network + private subnets)."
  value       = aws_db_subnet_group.main.name
}

output "engine_version_actual" {
  description = "Engine version efectiva (post apply; puede diferir de var.engine_version si AWS auto-upgrade)."
  value       = aws_db_instance.main.engine_version_actual
}

output "multi_az" {
  description = "Estado actual de Multi-AZ (puede cambiar dev=fasle -> prod=true)."
  value       = aws_db_instance.main.multi_az
}

output "backup_retention_period" {
  description = "Retention efectiva de backups automaticos."
  value       = aws_db_instance.main.backup_retention_period
}
