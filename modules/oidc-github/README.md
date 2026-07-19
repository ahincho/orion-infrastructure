# Module: oidc-github

Crea el IAM Identity Provider de GitHub Actions + 4 IAM roles OIDC (plan/apply × dev/prod).

## Uso

```hcl
module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name      = "orion"
  aws_region        = "us-east-1"
  github_repository = "ahincho/orion-infrastructure-devops"
}
```

## Outputs

| Output | Descripcion |
|---|---|
| `oidc_provider_arn` | ARN del IAM OIDC provider. |
| `oidc_provider_url` | URL del OIDC provider. |
| `terraform_plan_role_arn_dev` | ARN del role plan-dev. Wire a `AWS_PLAN_ROLE_ARN_DEV`. |
| `terraform_apply_role_arn_dev` | ARN del role apply-dev. Wire a `AWS_APPLY_ROLE_ARN_DEV`. |
| `terraform_plan_role_arn_prod` | ARN del role plan-prod. Wire a `AWS_PLAN_ROLE_ARN_PROD`. |
| `terraform_apply_role_arn_prod` | ARN del role apply-prod. Wire a `AWS_APPLY_ROLE_ARN_PROD`. |

## Decisiones

- **Trust policy por env (estricto)**: cada role SOLO acepta el `sub` claim de su env. Un token para `environment:dev` no puede asumir `*-prod`.
- **Plan roles**: read-only sobre AWS (EC2 describe, IAM get/list, KMS describe, S3 read). Defiende contra codigo malicioso en un PR que pueda exfiltrar el state pero no pueda crear/modificar recursos.
- **Apply roles**: full access scoped a la region (region lock via `aws:RequestedRegion`).
- **Lock de region**: previene que un role de dev aplique a una region inesperada.
- **Thumbprint**: 6938fd4d98bab03faadb97b34396831e3780aea1 (estable desde 2023). Si GitHub rota el cert raiz, actualizar `oidc_provider_thumbprint` via variable.
