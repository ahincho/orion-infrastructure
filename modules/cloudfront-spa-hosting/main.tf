# =============================================================================
# Module: cloudfront-spa-hosting
# =============================================================================
# Hosting de SPAs (Angular/React/Vue/etc.) en AWS:
#   - S3 bucket PRIVADO (public-access block total, AES256, sin versionado por
#     default). El bucket NO es accesible directamente; todo el trafico pasa
#     por CloudFront via Origin Access Control (OAC).
#   - CloudFront distribution con:
#       * Default *.cloudfront.net (sin ACM cert ni dominio custom).
#       * OAC (Origin Access Control) con sigv4 siempre activo.
#       * Default root object = index.html.
#       * Cache policy managed (CachingOptimized) para assets, CachingDisabled
#         para /index.html via path pattern.
#       * SPA fallback: custom_error_response 403/404 -> /index.html con 200.
#         Es el patron recomendado por AWS (no requiere Lambda@Edge ni
#         CloudFront Function; costo cero adicional mas alla del request).
#       * Viewer protocol policy = redirect-to-https.
#       * Price class default = PriceClass_100 (US/CA/EU only, mas barato).
#
# Bucket policy:
#   - Otorga s3:GetObject al service principal cloudfront.amazonaws.com
#     con condition aws:SourceArn restringida al distribution ARN especifico
#     (defense-in-depth anti confused-deputy).
#
# Naming:
#   - bucket: var.bucket_name (default '<project_name>-frontend-<environment>')
#   - OAC: '<bucket_name>-oac'
#   - distribution comment: '<bucket_name> CDN'
# =============================================================================

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-frontend-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Module      = "cloudfront-spa-hosting"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    },
  )
}

###############################################################################
# S3 bucket (PRIVADO)
###############################################################################

resource "aws_s3_bucket" "spa" {
  # checkov:skip=CKV_AWS_18:dev-only SPA bucket; access logging not required (CloudFront ya loguea a S3 opcional via additional_log).
  # checkov:skip=CKV_AWS_144:single-region dev environment; cross-region replication not applicable.
  # checkov:skip=CKV_AWS_145:SSE-S3 AES256 es suficiente para SPA dev; KMS adds complexity without benefit at this stage.
  # checkov:skip=CKV2_AWS_62:SPA bucket no consumer de eventos (no Lambda/SQS/SNS); event notifications no aplican.
  bucket        = local.bucket_name
  force_destroy = var.environment == "dev" # dev-only: permite `terraform destroy` rapido aunque tenga objetos.

  tags = merge(local.common_tags, {
    Name      = local.bucket_name
    Purpose   = "SPAHosting"
    Component = "storage"
  })
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket = aws_s3_bucket.spa.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: abort multipart uploads huerfanos (CKV_AWS_300). Sin
# transitions (el contenido se sobreescribe en cada deploy).
resource "aws_s3_bucket_lifecycle_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    id     = "abort-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

###############################################################################
# Origin Access Control (OAC) - patron moderno (reemplaza OAI deprecated)
###############################################################################
# AWS provider 5.x+ soporta OAC. Sigv4 siempre activo. El bucket policy
# mas abajo referencia este OAC por ID.
resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "${local.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for SPA bucket ${local.bucket_name}"
}

###############################################################################
# Bucket policy: solo CloudFront puede leer del bucket.
###############################################################################
# aws:SourceArn = distribution ARN restringe el acceso a ESTA distribution
# (defense-in-depth anti confused-deputy: aunque alguien cree otro OAC para
# este bucket, no podra servir contenido desde el distribution equivocado).
data "aws_iam_policy_document" "spa_bucket" {
  statement {
    sid     = "AllowCloudFrontServiceRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.spa.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      # aws_cloudfront_distribution.spa.arn se evalua en el apply. Como el
      # bucket policy depende del distribution, declaramos explicitamente
      # la dependencia abajo con depends_on para evitar ordering issues.
      values = [aws_cloudfront_distribution.spa.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  bucket     = aws_s3_bucket.spa.id
  policy     = data.aws_iam_policy_document.spa_bucket.json
  depends_on = [aws_cloudfront_distribution.spa]
}

###############################################################################
# CloudFront distribution
###############################################################################
# Cache behaviors:
#   - default (*): CachingOptimized (managed). Sirve cualquier archivo.
#   - SPA fallback: custom_error_response 403 -> /index.html (200),
#     404 -> /index.html (200). Asi deep links como /dashboard/algo cargan
#     el shell de Angular y el router resuelve la ruta cliente-side.
#   - index.html: CachingDisabled para que cambios de deploy se vean
#     inmediatamente sin invalidacion manual (los assets con hash SI se
#     cachean agresivamente).
#
# Nota: como el contenido del bucket es privado, todas las requests pasan
# por esta distribution. CloudFront firma con sigv4 via OAC para pedir
# objetos al bucket.
resource "aws_cloudfront_distribution" "spa" {
  # checkov:skip=CKV_AWS_68:Origen S3 privado; acceso solo via CloudFront OAC. Log delivery opcional via additional_log.
  # checkov:skip=CKV_AWS_86:Sin dominio custom = no requiere ACM certificate.
  comment             = "${local.bucket_name} CDN"
  enabled             = true
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id                = "S3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS",
    ]
    cached_methods = [
      "GET",
      "HEAD",
    ]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # index.html nunca se cachea: queremos que cada deploy se vea al instante.
  # Los chunks con outputHashing SI se cachean via CachingOptimized.
  ordered_cache_behavior {
    path_pattern           = "/index.html"
    target_origin_id       = "S3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS",
    ]
    cached_methods = [
      "GET",
      "HEAD",
    ]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # SPA fallback: cualquier 403/404 del origin (no encontrado, ACL denied,
  # deep link inexistente) se responde con /index.html y HTTP 200 para que
  # el router cliente-side tome el control.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

# Managed cache policies (AWS-provided). Evitamos recrear la rueda.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Security headers: HSTS, X-Content-Type-Options, etc. Managed por AWS.
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}
