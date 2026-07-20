output "bus_name" {
  description = "Nombre final del bus (resuelve default si bus_name vacio)."
  value       = aws_cloudwatch_event_bus.main.name
}

output "bus_arn" {
  description = "ARN del bus. Usar como IAM resource en policies events:PutEvents / Publish."
  value       = aws_cloudwatch_event_bus.main.arn
}

output "event_log_group_name" {
  description = "Nombre del CW Log Group que captura los eventos (null si enable_default_log_rule=false)."
  value       = try(aws_cloudwatch_log_group.event_log[0].name, null)
}

output "event_log_group_arn" {
  description = "ARN del CW Log Group (null si enable_default_log_rule=false). IAM Resource para policies."
  value       = try(aws_cloudwatch_log_group.event_log[0].arn, null)
}

output "events_log_writer_role_arn" {
  description = "ARN de la IAM role asumida por EventBridge para escribir al log group (null si enable_default_log_rule=false)."
  value       = try(aws_iam_role.events_log_writer[0].arn, null)
}

output "log_all_rule_arn" {
  description = "ARN de la regla 'log-all' (null si enable_default_log_rule=false)."
  value       = try(aws_cloudwatch_event_rule.log_all[0].arn, null)
}
