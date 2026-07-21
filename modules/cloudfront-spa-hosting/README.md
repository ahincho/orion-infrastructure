# Module: `cloudfront-spa-hosting`

Hosting de SPAs (Angular / React / Vue / Svelte) en AWS mediante
**S3 privado + CloudFront con Origin Access Control (OAC)**.

Patron recomendado por AWS en 2026 (sustituye al legacy OAI):

- Bucket S3 con `block_public_acls = true` en los 4 flags.
- Trafico solo via CloudFront; el bucket policy permite `s3:GetObject`
  al service principal `cloudfront.amazonaws.com` con condition
  `aws:SourceArn` restringida al distribution ARN especifico.
- OAC (no OAI) con `signing_behavior = "always"` y `signing_protocol = "sigv4"`.
- Default `*.cloudfront.net` (sin ACM cert ni dominio custom).

## Recursos que crea

| Recurso | Nombre | Proposito |
|---|---|---|
| `aws_s3_bucket` | `var.bucket_name` | Bucket privado para artefactos del SPA. AES256, sin versionado por default. |
| `aws_s3_bucket_public_access_block` | (idem) | 4 flags en `true`. |
| `aws_s3_bucket_server_side_encryption_configuration` | (idem) | SSE-S3 AES256. |
| `aws_s3_bucket_lifecycle_configuration` | (idem) | Aborta multipart uploads huerfanos a los 7 dias. |
| `aws_cloudfront_origin_access_control` | `<bucket_name>-oac` | OAC moderno (reemplaza OAI). |
| `aws_s3_bucket_policy` | (idem) | Otorga `s3:GetObject` solo al service principal CloudFront con `aws:SourceArn` condition. |
| `aws_cloudfront_distribution` | comment = `<bucket_name> CDN` | Distribution con SPA fallback + CachingDisabled para index.html. |

## Inputs

| Nombre | Tipo | Default | Descripcion |
|---|---|---|---|
| `project_name` | `string` | (requerido) | kebab-case, 3-30 chars. Validado. Usado como prefijo si `bucket_name` es vacio. |
| `environment` | `string` | (requerido) | `dev`/`staging`/`prod`. Validado. |
| `bucket_name` | `string` | `""` | Si vacio, default = `<project_name>-frontend-<environment>`. |
| `price_class` | `string` | `"PriceClass_100"` | `PriceClass_100` (US/CA/EU, mas barato), `PriceClass_200` o `PriceClass_All`. |
| `tags` | `map(string)` | `{}` | Tags adicionales. |

`force_destroy = true` solo si `environment == "dev"` para permitir
`terraform destroy` rapido cuando hay objetos adentro.

## Outputs

| Nombre | Descripcion |
|---|---|
| `bucket_id` | Nombre del bucket (sin ARN). |
| `bucket_arn` | ARN del bucket. |
| `bucket_domain_name` | Domain regional del bucket (`<bucket>.s3.<region>.amazonaws.com`). |
| `bucket_hosted_zone_id` | Hosted zone ID para alias Route53 si algun dia se anade dominio custom. |
| `distribution_id` | ID del CloudFront distribution. Usar como input en `angular-spa-deploy.yml` (campo `cloudfront-distribution-id`). |
| `distribution_arn` | ARN del distribution. |
| `distribution_domain_name` | URL publica del SPA (`dXXXX.cloudfront.net`). |
| `distribution_hosted_zone_id` | Hosted zone ID para alias Route53. |
| `oac_id` | ID del Origin Access Control. |

## SPA fallback

CloudFront `custom_error_response`:

- `403 -> /index.html` (200): cuando el bucket responde 403 (archivo no
  encontrado en una ruta sin extension), CF devuelve `index.html` con
  HTTP 200. El router cliente-side toma la ruta y resuelve.
- `404 -> /index.html` (200): mismo comportamiento para 404.

Esto cubre deep links como `/dashboard/algo` (Angular Router intercepta)
sin necesidad de Lambda@Edge ni CloudFront Function (costo $0 adicional).

## Cache strategy

- `default (*)` -> `Managed-CachingOptimized`. TTL minimo 1s, maximo 1 ano.
  Aplica a todos los chunks hasheados (`chunk-XXX.js`, `main.js`, etc.).
- `/index.html` -> `Managed-CachingDisabled`. Cada deploy se ve al instante
  sin invalidacion. Es seguro porque los chunks referenciados tienen hash
  en el nombre (output hashing de Angular): si cambia la app, cambia el
  nombre del chunk y `index.html` lo apunta al nuevo.

## Security headers

Se aplica `Managed-SecurityHeadersPolicy` a ambos cache behaviors. Anade:

- `Strict-Transport-Security`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy` (managed default - revisar antes de prod)

## Tags aplicados

- `Name = <bucket_name>`
- `Purpose = "SPAHosting"`
- `Component = "storage"`
- Tags default del provider (`Project`, `Environment`, `ManagedBy`, `Repository`).

## Skip de Checkov

- `CKV_AWS_18` - `access_logging` no requerido en dev (CF ya tiene su propio log opcional).
- `CKV_AWS_86` - Sin dominio custom = sin ACM cert que validar.
- `CKV_AWS_144` - Single-region dev (cross-region replica no aplica).
- `CKV_AWS_145` - SSE-S3 AES256 suficiente; KMS CMK cost ~$1/mes.
- `CKV2_AWS_62` - Bucket sin consumer de eventos (no Lambda/SQS/SNS).
- `CKV_AWS_68` - Origen S3 privado, acceso solo via OAC + CloudFront.

Razon por skip inline en `main.tf`.

## Wiring tipico (live/dev/main.tf)

```hcl
module "cloudfront_spa_hosting" {
  source       = "../../modules/cloudfront-spa-hosting"
  project_name = var.project_name
  environment  = var.environment
  price_class  = "PriceClass_100" # dev: solo US/EU/CA
  tags         = local.common_tags
}

# Outputs consumidos por orion-frontend via GH Secrets:
#   - module.cloudfront_spa_hosting.bucket_id                 -> S3_BUCKET (GH Variable, repo-scoped)
#   - module.cloudfront_spa_hosting.distribution_id           -> CLOUDFRONT_DISTRIBUTION_ID (GH Variable, repo-scoped)
#   - module.cloudfront_spa_hosting.distribution_domain_name  -> URL publica (referencia)
```

El modulo `iam-angular-spa-deploy-dev` (separado) crea el IAM role
asumible por GitHub Actions de `ahincho/orion-frontend` para hacer
`s3 sync --delete` + `cloudfront create-invalidation` en cada deploy.
