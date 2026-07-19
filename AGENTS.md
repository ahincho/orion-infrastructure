# AGENTS.md

> Convenciones operacionales para el repo `orion-infrastructure-devops`. Léase
> antes de cada PR. Es la fuente de verdad local (no se duplica en docs/).

---

## Proyecto

**ORION — Pequeño Sistema Cognitivo**. Repositorio parte de un monorepo de 5
repositorios coordinados (`orion-frontend`, `orion-backend`,
`orion-cognitive-agent`, `orion-article`).

## Stack

- **Cloud:** AWS (us-east-1, cuenta a confirmar por el owner)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 + native S3 lockfile (sin DynamoDB)
- **CI/CD:** GitHub Actions, reusable workflows desde
  `spark-match/spark-match-01-devops` (no tenemos reusables propios todavía).
- **Pin de reusables:** `@dev` para callers de dev, `@main` para callers de
  prod (replica la recomendación de `spark-match-01-devops/VERSIONING.md`).

## Branching

```
main (protegida, sin admin bypass)
  └── dev (admin bypass_mode: always)
        └── feat/<scope>-<name>
        └── fix/<scope>-<name>
        └── chore/<scope>-<name>
        └── docs/<scope>-<name>
```

- PR target: `dev`, NO `main` directamente.
- Promover a `main`: PR separado `dev → main` con comentario `chore: sync dev
  into main (post-phase-0)` o equivalente.
- Squash-only (regla del repo).
- Branch deletion on merge (regla del repo).
- Rulesets activos (3): `main - production`, `dev - integration`,
  `feature branches - flexible protection`.

## Secrets y GH Envs (estado actual)

Pendiente de crear (después del bootstrap):

- **GitHub Secrets (4):**
  - `AWS_PLAN_ROLE_ARN_DEV`
  - `AWS_APPLY_ROLE_ARN_DEV`
  - `AWS_PLAN_ROLE_ARN_PROD`
  - `AWS_APPLY_ROLE_ARN_PROD`
- **GitHub Environments (2):**
  - `dev` (sin reviewers, auto-approve=true en callers)
  - `production` (con ahincho como reviewer)

El script `scripts/setup-oidc.sh` crea los IAM roles en AWS.
El script `docs/SETUP.md` documenta los pasos para `gh secret set`.

## Convenciones Terraform

- **Provider:** AWS `~> 5.40` (fijo en `live/*/versions.tf` y
  `modules/*/versions.tf`).
- **Backend:** S3 + native lockfile (`use_lockfile = true`).
- **Tagging:** `default_tags` a nivel de provider (definido en
  `live/*/providers.tf`). Tags obligatorios: `Project=orion`,
  `Environment={dev|prod}`, `ManagedBy=terraform`, `Repository=ahincho/orion-infrastructure-devops`.
- **Naming:** `orion-<componente>-<env>-` para todos los recursos.
- **Validations:** usar `validation { condition = ... }` en variables
  (project_name kebab-case, environment en whitelist).
- **Outputs:** exponer ARNs de IAM y bucket name para wiring desde otros
  repos ORION vía `data "aws_ssm_parameter"` (futuro).

## Antes del primer apply

1. Decidir cuenta AWS y región (default `us-east-1`).
2. Correr `scripts/setup-oidc.sh` desde un workstation con AWS CLI configurado.
3. Configurar 4 GitHub Secrets y 2 GitHub Environments.
4. Correr `scripts/bootstrap-backend.sh` para crear los buckets de state.
5. `cd live/dev && terraform init && terraform plan`.

Si el primer apply falla, ver `docs/runbook-tfstate-recovery.md`.

## Contacto

- Owner: `@ahincho` (solo-dev).
- Slack: N/A.
- Decisiones arquitectónicas: este archivo + `README.md` + `docs/`.
