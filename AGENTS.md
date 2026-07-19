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
    workflows se declara en la repo-scoped variable `TF_VERSION`
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

## Convenciones Terraform / GH Actions vars

- **`TF_VERSION`** es la unica variable de GitHub Actions: repo-scoped
  (accesible desde cualquier workflow, incluyendo los callers de reusable
  workflows via `${{ vars.TF_VERSION }}`). Setear con
  `gh variable set TF_VERSION --body "1.15.7" --repo ahincho/orion-infrastructure`.
- **Resto de inputs** (environment, working-directory, aws-region, backend-bucket,
  backend-key, comment-on-pr, auto-approve) viven **hardcoded** en los
  workflows `terraform-plan.yml` y `terraform-apply.yml` por una razon
  tecnica concreta: un job que invoca un reusable workflow via `uses:` no
  puede declarar `environment:` (regla de GitHub Actions, actionlint lo
  detecta), y por tanto no puede acceder a GH Environment variables. La
  unica var accesible desde ese contexto son las repo-scoped.
- **Para production en el futuro** se duplica el caller con valores
  hardcoded para prod (`environment: prod`, `backend-bucket: orion-tfstate-prod`,
  etc.) — o se mantiene el caller y se usa un wrapper distinto. Ver
  seccion "Agregar un segundo AWS environment".

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
- **GitHub Variable (1):** repo-scoped, no sensible, versionado en
  codigo via `gh variable set`. Ver seccion arriba.
  - `TF_VERSION` = `1.15.7`.
- **GitHub Environment (1):**
  - `dev` — branch policy = `main`, sin reviewers, auto-approve=true.

El script `scripts/setup-oidc.sh` crea los IAM roles en AWS.
El script `docs/SETUP.md` documenta los pasos para `gh secret set`.

## Reglas duras (no negociables)

1. **Nunca** pegar AKIA / ASIA / access keys literales en archivos
   versionados. Solo referencias por nombre de perfil (`orion-admin`,
   `spark-match-admin`). Si necesitas el Key ID bajo un perfil, usa
   `aws configure get aws_access_key_id --profile <nombre>` en lugar
   de pegarlo en el codigo. **Si una key se filtra al repo por error,
   rotala inmediatamente en la consola de AWS** — el key ID viejo en
   `git log` es entonces texto muerto.
2. **Nunca** commitear `.tfstate`, `.terraform/`, `.terraform.lock.hcl`,
   ni archivos con secretos fuera de GH Secrets. `.gitignore` ya los
   excluye; respeta la convencion.
3. **Reglas de branching:** PR a `main` directo, squash-only, branch
   borrada tras merge. NO crear rama `dev/` ni `feature/*` larga vida.

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

1. Renombrar `live/dev/` a `live/prod/` (estructura existente).
2. Agregar un segundo remote module instance (e.g. `module.oidc_github_prod`)
   con OIDC para production.
3. Crear GitHub Environment `production` con branch policy = `main`
   (u otro ref que apunte a prod) y reviewer humano.
4. Duplicar los callers (`terraform-plan-prod.yml`,
   `terraform-apply-prod.yml`) con valores hardcoded para prod:
   `environment: prod`, `working-directory: live/prod`,
   `backend-bucket: orion-tfstate-prod`,
   `backend-key: prod/terraform.tfstate`,
   `auto-approve: false`, secrets con sufijo `_PROD`
   (`AWS_PLAN_ROLE_ARN_PROD`, `AWS_APPLY_ROLE_ARN_PROD`).
5. Los callers prod NO pueden tener `environment:` declarado
   (mismo motivo: invoca reusable via `uses:`), pero la GH Environment
   prod sigue siendo necesaria para que GH Actions evalue los reviewers
   + secrets de prod. Los secrets prod son los que se referencian
   desde inputs hardcoded del caller.

Por ahora NO se hace.

## Contacto

- Owner: `@ahincho` (solo-dev).
<!-- trigger ci lint -->

