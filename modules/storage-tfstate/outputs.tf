output "bucket_id" {
  description = "Nombre del bucket S3 creado."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  description = "ARN del bucket S3 creado."
  value       = aws_s3_bucket.tfstate.arn
}

output "bucket_region" {
  description = "Region donde se creo el bucket."
  value       = aws_s3_bucket.tfstate.region
}

output "bucket_domain_name" {
  description = "Domain name del bucket (sin protocol)."
  value       = aws_s3_bucket.tfstate.bucket_domain_name
}
