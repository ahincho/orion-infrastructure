# AGENTS.md

Convenciones operacionales para el repo `orion-infrastructure`. Lectura
obligatoria antes de cada PR. Fuente de verdad local (no duplicada en docs/).

---

## Proyecto

**ORION - Sistema Cognitivo**. Repositorio parte de un monorepo de 5
repositorios coordinados (`orion-frontend`, `orion-backend`,
`orion-cognitive-agent`, `orion-article`).

Este repo define la **infraestructura AWS del proyecto**.

## Stack

- **Cloud:** AWS (us-east-1, cuenta `681526276858` confirmada para dev)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
  - Validado en Terraform `1.15.7`. La version exacta que usan los
    workflows se declara en la GH Environment variable `TF_VERSION`
    (recomendamos bumpear `>= 1.6.0` solo cuando el floor cambie
    por una razon mayor; mantener el piso amplio permite correr
    con versiones futuras sin tocar los `versions.tf`).
- **AWS CLI local:** perfil `orion-admin` (AdministratorAccess).
  Alternativo: `spark-match-admin` (mismo nivel, otra cuenta de uso).
- **Backend:** S3 + native S3 lockfile (sin DynamoDB)
- **CI/CD:** GitHub Actions, reusable workflows desde
  `spark-match/spark-match-01-devops` (pinneados `@dev`).
- **Pin de reusables:** siempre `@dev` (este repo solo tiene dev).
- **Ambientes AWS:** 1 unico (`dev`). No hay production.

## Branching

```
main (protegida, 1 ruleset)
  â””â”€â”€ feat/<scope>-<name>
  â””â”€â”€ fix/<scope>-<name>
  â””â”€â”€ chore/<scope>-<name>
  â””â”€â”€ docs/<scope>-<name>
  â””â”€â”€ ci/<scope>-<name>
```

- PR target: `main` directamente (no hay dev intermedia).
- Squash-only (regla del repo).
- Branch deletion on merge (regla del repo).
- Ruleset activo (1): `main - default protection` (deletion + non_fast_forward).

## Secrets y GH Env (estado actual)

Pendiente de crear (despues del bootstrap):

- **GitHub Secrets (2):** valores sensibles. Cifrados en reposo.
  - `AWS_PLAN_ROLE_ARN` — ARN del IAM role `orion-terraform-plan`
    (read-only, asumido por GH Actions en PRs contra `main`).
  - `AWS_APPLY_ROLE_ARN` — ARN del IAM role `orion-terraform-apply`
    (write, restringido por `aws:RequestedRegion` a `us-east-1`).
- **GitHub Environment (1):**
  - `dev` — branch policy = `main`, sin reviewers, auto-approve=true.

### Variables del GH Environment `dev`

Toda la config que antes estaba quemada en los workflows ahora vive
en variables del environment `dev`. Para replicar a otro ambiente
(p.ej. `production`) basta duplicar las variables; los workflows
no se tocan.

| Variable | Valor dev | Proposito |
|---|---|---|
| `ENV_NAME` | `dev` | nombre logico del ambiente |
| `TF_VERSION` | `1.15.7` | version Terraform usada por los jobs |
| `AWS_REGION` | `us-east-1` | region AWS por defecto |
| `TF_WORKING_DIR` | `live/dev` | directorio donde corre `terraform` |
| `TF_BACKEND_BUCKET` | `orion-tfstate-dev` | bucket S3 del state |
| `TF_BACKEND_KEY` | `dev/terraform.tfstate` | ruta interna del state |
| `TF_COMMENT_ON_PR` | `true` | plan postea comentario en PR |
| `TF_AUTO_APPROVE` | `true` | apply no pide reviewer (dev only) |

Los nombres de los Secrets (`AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`)
quedan literales en los `with:` porque apuntan a la entrada del secret,
no a su valor.

El script `scripts/setup-oidc.sh` crea los IAM roles en AWS.
El script `docs/SETUP.md` documenta los pasos para `gh secret set`.

## Convenciones Terraform

- **Provider:** AWS `~> 5.40` (fijo en `live/dev/versions.tf` y
  `modules/*/versions.tf`).
- **Backend:** S3 + native lockfile (`use_lockfile = true`).
- **Tagging:** `default_tags` a nivel de provider (definido en
  `live/dev/providers.tf`). Tags obligatorios: `Project=orion`,
  `Environment=dev`, `ManagedBy=terraform`, `Repository=ahincho/orion-infrastructure`.
- **Naming:** `orion-<componente>-<env>-` para todos los recursos.
- **Validations:** usar `validation { condition = ... }` en variables
  (project_name kebab-case, environment == "dev").
- **Outputs:** exponer ARNs de IAM y bucket name para wiring desde otros
  repos ORION via `data "aws_ssm_parameter"` (futuro).

## Antes del primer apply

1. Decidir cuenta AWS y region (default `us-east-1`).
2. Correr `./scripts/setup-oidc.sh` desde un workstation con AWS CLI.
3. Configurar 2 GitHub Secrets y 1 GitHub Environment.
4. Correr `./scripts/bootstrap-backend.sh` para crear el bucket de state.
5. `cd live/dev && terraform init && terraform plan`.

Si el primer apply falla, ver `docs/runbook-tfstate-recovery.md`.

## Agregar un segundo AWS environment (futuro)

Si mas adelante se quiere producir a production:

1. Renombrar `live/dev/` a `live/<env_name>/` (estructura existente).
2. Agregar un segundo remote module instance (e.g. `module.oidc_github_prod`)
   con OIDC para production.
3. Crear GitHub Environment `production` y duplicar las 8 variables
   de la tabla anterior (`ENV_NAME=production`, `TF_WORKING_DIR=live/prod`,
   `TF_BACKEND_BUCKET=orion-tfstate-prod`, `TF_BACKEND_KEY=prod/terraform.tfstate`,
   `TF_AUTO_APPROVE=false`, etc.). Los workflows no necesitan cambios.
4. Anadir reviewer humano al environment `production`.
5. Crear Secrets `AWS_PLAN_ROLE_ARN_PROD` y `AWS_APPLY_ROLE_ARN_PROD`
   (nombres distintos para evitar confusion) y ajustar workflows
   si los nombres divergen entre envs.

Por ahora NO se hace.

## Contacto

- Owner: `@ahincho` (solo-dev).