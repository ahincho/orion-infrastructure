output "bucket_id" {
  description = "Nombre del bucket S3 (e.g. 'orion-frontend-dev')."
  value       = aws_s3_bucket.spa.id
}

output "bucket_arn" {
  description = "ARN del bucket S3."
  value       = aws_s3_bucket.spa.arn
}

output "bucket_domain_name" {
  description = "Domain name regional del bucket (formato <bucket>.s3.<region>.amazonaws.com)."
  value       = aws_s3_bucket.spa.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Hosted zone ID del bucket (necesario para alias records en Route53 si en algun momento se anade dominio custom)."
  value       = aws_s3_bucket.spa.hosted_zone_id
}

output "distribution_id" {
  description = "ID del CloudFront distribution. Usar como input distribution-id en reusable angular-spa-deploy.yml para create-invalidation."
  value       = aws_cloudfront_distribution.spa.id
}

output "distribution_arn" {
  description = "ARN del CloudFront distribution."
  value       = aws_cloudfront_distribution.spa.arn
}

output "distribution_domain_name" {
  description = "Domain name del CloudFront distribution (e.g. 'd111111abcdef8.cloudfront.net'). URL publica del SPA."
  value       = aws_cloudfront_distribution.spa.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Hosted zone ID del CloudFront distribution (necesario para alias records en Route53)."
  value       = aws_cloudfront_distribution.spa.hosted_zone_id
}

output "oac_id" {
  description = "ID del Origin Access Control creado para esta distribution."
  value       = aws_cloudfront_origin_access_control.spa.id
}
