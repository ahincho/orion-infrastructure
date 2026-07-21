# Module: `iam-angular-spa-deploy-dev`

Crea el IAM role + inline policy `AngularSpaDeployPolicy` que asume el
workflow `CD - Deploy` de [`ahincho/orion-frontend`][frontend] via GitHub
OIDC para hacer `aws s3 sync --delete` y `aws cloudfront create-invalidation`
contra el bucket + distribution creados por `modules/cloudfront-spa-hosting`.

[frontend]: https://github.com/ahincho/orion-frontend

## Naming

`<project_name>-angular-spa-deploy-<environment>` -> `orion-angular-spa-deploy-dev`.

## Outputs

| Output | Descripcion |
|---|---|
| `role_arn` | ARN del IAM role. Wire a GitHub Environment secret `AWS_DEPLOY_ROLE_ARN` (orion-frontend / env: dev). |
| `role_name` | Nombre del role (sin ARN). |
| `role_id` | ID estable (role-unique). |

## Trust policy

Asumible solo desde:

- `repo:ahincho/orion-frontend:ref:refs/heads/main` (push a main)
- `repo:ahincho/orion-frontend:environment:dev` (jobs con `environment: dev`)

No aceptable desde forks, otras branches, ni el repo spark-match
ni `orion-infrastructure`.

## Permisos (`AngularSpaDeployPolicy`)

3 statements inline:

| Statement | Scope |
|---|---|
| `S3ManageObjects` | `arn:aws:s3:::<bucket_name>` + `arn:aws:s3:::<bucket_name>/*` (read+write+delete+list) |
| `CloudFrontInvalidateDistribution` | `arn:aws:cloudfront::<account>:distribution/<distribution_id>` (create/get/list invalidations) |
| `STSGetCallerIdentity` | `*` (requerido por `aws-actions/configure-aws-credentials`) |

Los ARN son dinamicos via `var.bucket_name` y `var.cloudfront_distribution_id`,
construidos a partir de los outputs de `modules/cloudfront-spa-hosting`.

## Wiring tipico (live/dev/main.tf)

```hcl
module "cloudfront_spa_hosting" {
  source       = "../../modules/cloudfront-spa-hosting"
  project_name = var.project_name
  environment  = var.environment
  price_class  = "PriceClass_100"
  tags         = local.common_tags
}

module "iam_angular_spa_deploy_dev" {
  source                     = "../../modules/iam-angular-spa-deploy-dev"
  project_name               = var.project_name
  environment                = var.environment
  aws_region                 = var.aws_region  # legacy: kept as comment for context, var was dropped
  oidc_provider_arn          = module.oidc_github.oidc_provider_arn
  github_repository          = "ahincho/orion-frontend"
  bucket_name                = module.cloudfront_spa_hosting.bucket_id
  cloudfront_distribution_id = module.cloudfront_spa_hosting.distribution_id
  tags                       = local.common_tags
}
```
