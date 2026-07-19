# SETUP - Configuracion inicial del repo

> Pasos para llevar el repo de Phase 0 (codigo commiteado) a Phase 0
> deployed (state bucket + IAM roles + GH Secrets + GH Env).
>
> **Asume que el codigo esta en `main`.** No hay rama dev intermedia.

---

## Pre-requisitos

- AWS CLI configurado con un usuario/role que tenga permisos de `iam:*` y `s3:*`
- GitHub CLI autenticado como `@ahincho` con permisos de admin en
  `ahincho/orion-infrastructure`
- Cuenta AWS y region confirmados (default: `us-east-1`)

---

## Paso 1: Bootstrap manual del state bucket

Terraform no puede crear su propio state bucket (chicken-and-egg). Antes del
primer apply, crear el bucket via el script:

```bash
ENVIRONMENT=dev AWS_REGION=us-east-1 ./scripts/bootstrap-backend.sh
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
- 2 IAM roles OIDC (plan + apply)

Anotar los 2 ARNs de los roles:

```bash
terraform output -json | jq -r '"plan=" + .terraform_plan_role_arn.value, "apply=" + .terraform_apply_role_arn.value'
```

---

## Paso 3: Crear GitHub Secrets

```bash
REPO="ahincho/orion-infrastructure"

PLAN_ARN="arn:aws:iam::{account_id}:role/orion-terraform-plan"
APPLY_ARN="arn:aws:iam::{account_id}:role/orion-terraform-apply"

gh secret set AWS_PLAN_ROLE_ARN  --repo "$REPO" --body "$PLAN_ARN"
gh secret set AWS_APPLY_ROLE_ARN --repo "$REPO" --body "$APPLY_ARN"
```

Verificar:

```bash
gh secret list --repo "$REPO"
```

---

## Paso 4: Crear GitHub Environment `dev`

```bash
REPO="ahincho/orion-infrastructure"

gh api --method PUT "repos/$REPO/environments/dev" \
  --input <(cat <<'"'"'JSON'"'"'
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
  --input <(echo '"'"'{"name":"main"}'"'"')
```

Resultado: env `dev` permite deployments solo desde la branch `main`. Sin
reviewers, auto-aprueba.

---

## Paso 5: Validar el flujo end-to-end

### Disparar plan en PR

Crear una rama `feat/test-oidc` desde `main` con un cambio trivial:

```bash
git checkout main
git pull origin main
git checkout -b feat/test-oidc
echo "# $(date)" > live/dev/test.txt
git add live/dev/test.txt
git commit -m "chore: test OIDC plan"
git push -u origin feat/test-oidc
gh pr create --base main --head feat/test-oidc --title "chore: test OIDC plan" --body "Test OIDC plan dispatch"
```

Verificar que `CI - Terraform Plan` corre (se necesita `AWS_PLAN_ROLE_ARN`).

### Disparar apply via merge

Merge el PR a `main` (squash). Verificar que `CD - Terraform Apply` corre sin
errores de AssumeRoleWithWebIdentity.

Limpiar:

```bash
git revert HEAD
# o borrar el archivo test.txt del PR y mergear un revert
```

### Disparar apply via dispatch (opcional, no mergea)

Si se quiere validar el role sin mergear, ir a Actions â†’ `CD - Terraform Apply`
â†’ Run workflow (sin inputs requeridos).

---

## Troubleshooting

| Error | Causa probable | Solucion |
|---|---|---|
| `Error: error creating IAM OIDC Provider` | Ya existe un OIDC provider en la cuenta | Confirmar con `aws iam get-open-id-connect-provider-arn`; Terraform import o skip del recurso |
| `Error: AccessDenied: s3:PutObject on ...tfstate.tflock` | Plan tratando de usar lock | El caller usa `-lock=false` (ya esta en el reusable) |
| `Error: Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch/environment | Verificar el output del modulo y el `sub` claim del token |
| `Error: Credentials could not be loaded` | Secret no configurado o role no existe | `gh secret list --repo ...` y `aws iam get-role --role-name ...` |
| `Error: aws:...:CreateRole exceeded maximum` | Cada AWS account tiene un limite de IAM roles | Solicitar aumento de quota o consolidar roles |

---

## Checklist post-setup

- [ ] Bucket `orion-tfstate-dev` creado y verificado
- [ ] 1 IAM OIDC provider creado
- [ ] 2 IAM roles creados
- [ ] 2 GitHub Secrets configurados
- [ ] 1 GitHub Environment (`dev`) creado con branch policy `main`
- [ ] Workflow `CI - Terraform Plan` corrido al menos una vez en un PR
- [ ] Workflow `CD - Terraform Apply` corrido via push a main (o via dispatch)