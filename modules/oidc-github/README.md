# Module: oidc-github

Crea el IAM OIDC provider para GitHub Actions + 2 IAM roles para Terraform
sobre el ambiente dev.

## Recursos

| Recurso | Nombre | Permisos |
|---|---|---|
| `aws_iam_openid_connect_provider.github` | (sin nombre) | OIDC issuer `token.actions.githubusercontent.com` |
| `aws_iam_role.plan` | `orion-terraform-plan` | read-only (`ec2:Describe*`, `iam:Get*`, `iam:List*`, `kms:Describe*`, `s3:Get*`, `s3:List*`, `sts:GetCallerIdentity`) |
| `aws_iam_role.apply` | `orion-terraform-apply` | `Action: "*"` restringido a `aws:RequestedRegion` |

## Trust policy (ambos roles)

Los roles SOLO pueden ser asumidos cuando el OIDC token cumple:

- `aud = sts.amazonaws.com`
- `sub` matches:
  - `repo:<github_repository>:ref:refs/heads/main`
  - `repo:<github_repository>:pull_request`
  - `repo:<github_repository>:environment:dev`

Es decir: cualquier push o PR contra `main` del repo del caller, o cualquier
job con `environment:dev`, puede asumir los roles. Si en el futuro se
quiere producir a otro AWS environment, generar otro modulo o parametrizar.

## Outputs

- `oidc_provider_arn` â€” ARN del OIDC provider.
- `oidc_provider_url` â€” URL del issuer.
- `terraform_plan_role_arn` â€” ARN del role plan (para GitHub Secret `AWS_PLAN_ROLE_ARN`).
- `terraform_apply_role_arn` â€” ARN del role apply (para GitHub Secret `AWS_APPLY_ROLE_ARN`).

## Uso

```hcl
module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name      = "orion"
  aws_region        = "us-east-1"
  github_repository = "ahincho/orion-infrastructure"
}

output "plan_arn"  { value = module.oidc_github.terraform_plan_role_arn }
output "apply_arn" { value = module.oidc_github.terraform_apply_role_arn }
```