output "vpc_id" {
  description = "ID del VPC principal."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block del VPC (IPv4)."
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN del VPC."
  value       = aws_vpc.main.arn
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas, ordenadas por AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas, ordenadas por AZ."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs de las subnets publicas."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDRs de las subnets privadas."
  value       = aws_subnet.private[*].cidr_block
}

output "private_route_table_ids" {
  description = "IDs de las route tables privadas (1 por AZ o 1 sola si single_nat_gateway=true)."
  value       = aws_route_table.private[*].id
}

output "vpc_endpoint_security_group_id" {
  description = "SG aplicado a los Interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_vpc_endpoint_id" {
  description = "ID del VPC Gateway endpoint para S3."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "interface_vpc_endpoint_security_group_id" {
  description = "Alias de vpc_endpoint_security_group_id (compatibilidad hacia otros modulos)."
  value       = aws_security_group.vpc_endpoints.id
}

output "flow_log_id" {
  description = "ID del VPC flow log."
  value       = aws_flow_log.main.id
}

output "azs" {
  description = "Availability Zones usadas (post-data-source resolution)."
  value       = local.azs
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs publicas de los NAT Gateway(s)."
  value       = aws_eip.nat[*].public_ip
}
