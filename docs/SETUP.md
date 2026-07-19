# SETUP - Configuracion inicial del repo

> Pasos para llevar el repo de Phase 0 (codigo commiteado) a Phase 0
> deployed (state bucket + IAM roles + GH Secrets + GH Envs).
>
> **Asume que el codigo del PR (`feat/phase-0-bootstrap -> dev`) ya fue mergeado.**

---

## Pre-requisitos

- AWS CLI configurado con un usuario/role que tenga permisos de `iam:*` y `s3:*`
- GitHub CLI autenticado como `@ahincho` con permisos de admin en
  `ahincho/orion-infrastructure-devops`
- Cuenta AWS y region confirmados (default: `us-east-1`)

---

## Paso 1: Bootstrap manual del state bucket (UNA VEZ por env)

Terraform no puede crear su propio state bucket (chicken-and-egg).
Antes del primer apply, crear el bucket via el script:

```bash
# Dev
ENVIRONMENT=dev AWS_REGION=us-east-1 ./scripts/bootstrap-backend.sh

# Prod
ENVIRONMENT=prod AWS_REGION=us-east-1 ./scripts/bootstrap-backend.sh
```

Verificar:

```bash
aws s3api get-bucket-versioning --bucket orion-tfstate-dev
aws s3api get-bucket-encryption --bucket orion-tfstate-dev
aws s3api get-public-access-block --bucket orion-tfstate-dev
```

Esperado: `Status=Enabled`, `SSEAlgorithm=AES256`, todos los flags `true`.

---

## Paso 2: Primera aplicacion del modulo oidc-github

```bash
cd live/dev

terraform init -backend-config="bucket=orion-tfstate-dev" \
               -backend-config="key=dev/terraform.tfstate" \
               -backend-config="region=us-east-1" \
               -backend-config="use_lockfile=true"

terraform plan
terraform apply
```

Esto crea:
- 1 IAM OIDC provider para GitHub Actions
- 4 IAM roles OIDC (plan/apply x dev/prod)
- Resource policy `null` para `aws_s3_bucket.tfstate` (ya existe, lectura)

Anotar los 4 ARNs de los roles:

```bash
terraform output -json | jq -r '
  {
    plan_dev:   .terraform_plan_role_arn_dev.value,
    apply_dev:  .terraform_apply_role_arn_dev.value,
    plan_prod:  .terraform_plan_role_arn_prod.value,
    apply_prod: .terraform_apply_role_arn_prod.value
  } | to_entries[] | "\(.key)=\(.value)"
'
```

Repetir para prod si se hizo bootstrap prod (alternativamente, los roles
se crean en dev y se quedan en prod — son globales en AWS).

---

## Paso 3: Crear GitHub Secrets

```bash
REPO="ahincho/orion-infrastructure-devops"

PLAN_DEV_ARN="arn:aws:iam::{account_id}:role/orion-terraform-plan-dev"
APPLY_DEV_ARN="arn:aws:iam::{account_id}:role/orion-terraform-apply-dev"
PLAN_PROD_ARN="arn:aws:iam::{account_id}:role/orion-terraform-plan-prod"
APPLY_PROD_ARN="arn:aws:iam::{account_id}:role/orion-terraform-apply-prod"

gh secret set AWS_PLAN_ROLE_ARN_DEV  --repo "$REPO" --body "$PLAN_DEV_ARN"
gh secret set AWS_APPLY_ROLE_ARN_DEV --repo "$REPO" --body "$APPLY_DEV_ARN"
gh secret set AWS_PLAN_ROLE_ARN_PROD --repo "$REPO" --body "$PLAN_PROD_ARN"
gh secret set AWS_APPLY_ROLE_ARN_PROD --repo "$REPO" --body "$APPLY_PROD_ARN"
```

Verificar:
```bash
gh secret list --repo "$REPO"
```

---

## Paso 4: Crear GitHub Environments

### dev (sin reviewers, auto-aprueba)

```bash
gh api --method PUT "repos/$REPO/environments/dev" \
  --input <(cat <<'JSON'
{
  "wait_timer": 0,
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
)

gh api --method POST "repos/$REPO/environments/dev/deployment-branch-policies" \
  --input <(echo '{"name":"dev"}')
```

### production (con reviewer `@ahincho`)

```bash
USER_ID=$(gh api user --jq '.id' | xargs)
# Si gh api user falla (EMU restrictions), usar el ID hardcodeado del
# owner (lo encuentras en la config de admins de la org).

gh api --method PUT "repos/$REPO/environments/production" \
  --input <(cat <<JSON
{
  "wait_timer": 0,
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  },
  "reviewers": [
    {"type": "User", "id": ${USER_ID}}
  ]
}
JSON
)

gh api --method POST "repos/$REPO/environments/production/deployment-branch-policies" \
  --input <(echo '{"name":"main"}')
```

---

## Paso 5: Validar el flujo end-to-end

### Disparar plan en PR

Crear una rama `feat/test-oidc` desde `dev` con un cambio trivial:

```bash
git checkout dev
git pull origin dev
git checkout -b feat/test-oidc
echo "# test" >> /tmp/marker.md
# Crear un archivo dummy
mkdir -p live/dev
echo "# $(date)" > live/dev/test.txt
git add live/dev/test.txt
git commit -m "chore: test OIDC plan"
git push -u origin feat/test-oidc
gh pr create --base dev --head feat/test-oidc --title "chore: test OIDC plan" --body "Test OIDC plan dispatch"
```

Verificar que `CI - Terraform Plan` corre (se necesita `AWS_PLAN_ROLE_ARN_DEV` configurado).

### Disparar apply via dispatch

1. Mergear el PR de prueba a `dev` (squash).
2. Ir a la pestana Actions del repo.
3. Seleccionar workflow `CD - Terraform Apply`.
4. Run workflow con `environment=dev`.
5. Verificar que corre sin errores de AssumeRoleWithWebIdentity.

Limpiar:

```bash
git revert HEAD
# o borrar el archivo test.txt del PR y mergear un revert
```

---

## Troubleshooting

| Error | Causa probable | Solucion |
|---|---|---|
| `Error: error creating IAM OIDC Provider` | Ya existe un OIDC provider en la cuenta | Confirmar con `aws iam get-open-id-connect-provider-arn`; Terraform import o skip del recurso |
| `Error: AccessDenied: s3:PutObject on ...tfstate.tflock` | Plan tratando de usar lock | El caller usa `-lock=false` (ya esta en el reusable) |
| `Error: Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch | Verificar el output del modulo y el `sub` claim del token |
| `Error: Credentials could not be loaded` | Secret no configurado o role no existe | `gh secret list --repo ...` y `aws iam get-role --role-name ...` |
| `Error: aws:...:CreateRole exceeded maximum` | Cada AWS account tiene un limite de IAM roles | Solicitar aumento de quota o consolidar roles |

---

## Checklist post-setup

- [ ] 2 state buckets creados (`orion-tfstate-dev`, `orion-tfstate-prod`)
- [ ] 1 IAM OIDC provider creado
- [ ] 4 IAM roles creados
- [ ] 4 GitHub Secrets configurados
- [ ] 2 GitHub Environments creados (`dev`, `production`)
- [ ] Workflow `CI - Terraform Plan` corrido al menos una vez en un PR
- [ ] Workflow `CD - Terraform Apply - dev` corrido via dispatch
- [ ] Workflow `CD - Terraform Apply - prod` corrido via push a main (o via dispatch)
