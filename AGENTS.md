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
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 6.55`
  - Validado en Terraform `1.15.7`. La version exacta que usan los
    workflows se declara en la repo-scoped variable `TF_VERSION`
    (recomendamos bumpear `>= 1.6.0` solo cuando el floor cambie
    por una razon mayor; mantener el piso amplio permite correr
    con versiones futuras sin tocar los `versions.tf`).
- **AWS CLI local:** perfil `orion-admin` (AdministratorAccess).
  Alternativo: `spark-match-admin` (mismo nivel, otra cuenta de uso).
- **Backend:** S3 + native S3 lockfile (sin DynamoDB)
- **CI/CD:** GitHub Actions, reusable workflows desde
  `spark-match/spark-match-01-devops` (pinneados `@main`).
- **Pin de reusables:** siempre `@main`. Los reusables fueron promovidos de
  `@dev` -> `@main` despues de validacion end-to-end (PR #24 con 8/8 checks
  verdes + spark-match-01-devops PR #45). Futuros cambios en reusables se
  prueban primero en `@dev` y se promueve en una segunda PR.
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
  etc.) â€” o se mantiene el caller y se usa un wrapper distinto. Ver
  seccion "Agregar un segundo AWS environment".

## Branching

```
main (protegida, 1 ruleset)
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ feat/<scope>-<name>
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ fix/<scope>-<name>
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ chore/<scope>-<name>
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ docs/<scope>-<name>
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ ci/<scope>-<name>
```

- PR target: `main` directamente (no hay dev intermedia).
- Squash-only (regla del repo).
- Branch deletion on merge (regla del repo).
- Ruleset activo (1): `main - default protection` (deletion + non_fast_forward).

## Secrets y GH Env (estado actual)

Pendiente de crear (despues del bootstrap):

- **GitHub Secrets (2):** valores sensibles. Cifrados en reposo.
  - `AWS_PLAN_ROLE_ARN` â€” ARN del IAM role `orion-terraform-plan`
    (read-only, asumido por GH Actions en PRs contra `main`).
  - `AWS_APPLY_ROLE_ARN` â€” ARN del IAM role `orion-terraform-apply`
    (write, restringido por `aws:RequestedRegion` a `us-east-1`).
- **GitHub Variable (1):** repo-scoped, no sensible, versionado en
  codigo via `gh variable set`. Ver seccion arriba.
  - `TF_VERSION` = `1.15.7`.
- **GitHub Environment (1):**
  - `dev` â€” branch policy = `main`, sin reviewers, auto-approve=true.

El script `scripts/setup-oidc.sh` crea los IAM roles en AWS.
El script `docs/SETUP.md` documenta los pasos para `gh secret set`.

## Reglas duras (no negociables)

1. **Nunca** pegar AKIA / ASIA / access keys literales en archivos
   versionados. Solo referencias por nombre de perfil (`orion-admin`,
   `spark-match-admin`). Si necesitas el Key ID bajo un perfil, usa
   `aws configure get aws_access_key_id --profile <nombre>` en lugar
   de pegarlo en el codigo. **Si una key se filtra al repo por error,
   rotala inmediatamente en la consola de AWS** â€” el key ID viejo en
   `git log` es entonces texto muerto.
2. **Nunca** commitear `.tfstate`, `.terraform/`, ni archivos con
   secretos fuera de GH Secrets. `.gitignore` ya los excluye; respeta
   la convencion.
   
   **Excepcion:** `.terraform.lock.hcl` **SI se commitea** (uno por
   directorio con `versions.tf`) para garantizar reproducibilidad de
   providers en CI/CD. El `.gitignore` lo permite explicitamente con
   `!*.terraform.lock.hcl`.
3. **Reglas de branching:** PR a `main` directo, squash-only, branch
   borrada tras merge. NO crear rama `dev/` ni `feature/*` larga vida.

## Convenciones Terraform

- **Provider:** AWS `~> 6.55` (fijo en `live/dev/versions.tf` y
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


## orion-cognitive-agent infra (Phase 1.6)

Modulos en `modules/` que provisionan recursos consumidos por
[`ahincho/orion-cognitive-agent`][cog] (Bedrock AgentCore Runtime deploys):

| Modulo | Recursos | Consumido por |
|---|---|---|
| `modules/ecr-orion-agent-core` | ECR repo privado (`<project>-agent-core-<env>`) AES256 + scan_on_push + lifecycle policy | Deploy job + AgentCore Runtime execution role (pull imagen) |
| `modules/iam-orion-agent-core-deploy` | GitHub OIDC role (`<project>-agent-core-deploy-<env>`) con permisos granulares sobre AgentCore + Bedrock + ECR | Repo `ahincho/orion-cognitive-agent` (workflows en main branch) |
| `modules/iam-orion-agent-core-runtime` | IAM role asumido por el contenedor dentro de Bedrock AgentCore (`<project>-agent-core-runtime-<env>`) con permisos Bedrock InvokeModel + CloudWatch logs | Bedrock AgentCore Runtime (trust `bedrock-agentcore.amazonaws.com`) |
| `modules/bedrock-agent-core-runtime` *(futuro, PR #45)* | `aws_bedrockagentcore_agent_runtime` + `aws_bedrockagentcore_agent_runtime_endpoint` | Bedrock AgentCore Runtime (deploys subsecuentes) |

Wire up al wiring de `live/dev/main.tf` (despues del modulo `ssm-bootstrap`):

```hcl
module "ecr_orion_agent_core" {
  source          = "../../modules/ecr-orion-agent-core"
  project_name    = var.project_name
  environment     = var.environment
  image_tag_mutability = "MUTABLE" # dev only
  scan_on_push         = true
  max_image_count      = 20
  tags                 = local.common_tags
}

module "iam_orion_agent_core_deploy" {
  source            = "../../modules/iam-orion-agent-core-deploy"
  project_name      = var.project_name
  environment       = var.environment
  github_repository = "ahincho/orion-cognitive-agent"
  oidc_provider_arn  = module.oidc_github.oidc_provider_arn
  ecr_repository_arn = module.ecr_orion_agent_core.repository_arn

  # Permite al deploy job PassRole hacia AgentCore (PR #45).
  agentcore_runtime_role_arns = [
    module.iam_orion_agent_core_runtime.runtime_role_arn,
  ]

  tags = local.common_tags
}

module "iam_orion_agent_core_runtime" {
  source       = "../../modules/iam-orion-agent-core-runtime"
  project_name = var.project_name
  environment  = var.environment

  # runtime_arn = "" (default; se actualiza tras PR #45 para tightens trust).

  tags = local.common_tags
}

# Cross-cycle resource: deploy role + runtime role deben poder pull del ECR.
# Fuera de los modulos para romper el ciclo ecr <-> iam (deploy) <-> iam (runtime).
resource "aws_ecr_repository_policy" "orion_agent_core" {
  repository = module.ecr_orion_agent_core.repository_name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowPullForOrionAgentCorePrincipals"
      Effect    = "Allow"
      Principal = { AWS = [deploy_arn, runtime_arn] }
      Action    = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", ...]
    }]
  })
}
```

Outputs en `live/dev/outputs.tf`:

- `orion_agent_core_deploy_role_arn` -> wire a GitHub Secret `AGENT_DEPLOY_ROLE_ARN` en `orion-cognitive-agent`.
- `orion_agent_core_ecr_repository_uri` -> registry URL del ECR repo.
- `orion_agent_core_runtime_role_arn` -> wire como `role_arn` en el modulo `bedrock-agent-core-runtime` (PR #45).
- (futuro) `orion_agent_core_runtime_id`, `orion_agent_core_runtime_arn`, `orion_agent_core_runtime_endpoint_arn`.

### Ciclo `ecr <-> iam (deploy)` y `ecr <-> iam (runtime)` y como se rompe

1. `iam_orion_agent_core_deploy` necesita `ecr_repository_arn` (input del modulo).
2. `iam_orion_agent_core_runtime` no tiene esa dependencia, pero su output (`runtime_role_arn`) aparece como input en `iam_orion_agent_core_deploy.agentcore_runtime_role_arns` (PassRole).
3. ECR repo policy (`aws_ecr_repository_policy`) necesita permitir pull al deploy role + al runtime role (outputs de los modulos iam).
4. **Solucion**: el modulo ECR NO acepta `principal_arns_with_pull` por default (queda `[]`). En `live/dev/main.tf` declaramos `aws_ecr_repository_policy.orion_agent_core` que referencia `module.iam_orion_agent_core_deploy.deploy_role_arn` Y `module.iam_orion_agent_core_runtime.runtime_role_arn` directamente (fuera del modulo ECR). Asi no hay cycles y la policy es editable sin reemplazar el modulo.

### Trust del runtime role: 2-fases bootstrap

El role de runtime no puede tightens su trust con `aws:SourceArn = <runtime_arn>` hasta que el AgentRuntime exista (PR #45). El patron actual:

1. **Fase 1 (este PR)**: `var.runtime_arn = ""` (default). Trust solo permite el service principal (`bedrock-agentcore.amazonaws.com`), cualquier AgentRuntime de la cuenta podria assumir el role (looser, sirve para bootstrap).
2. **Fase 2 (futuro, despues de PR #45)**: tras crear el AgentRuntime, copiar su `agent_runtime_arn` output del modulo `bedrock-agent-core-runtime` al param `runtime_arn` del modulo `iam_orion-agent-core-runtime` en `live/dev/main.tf`, y re-aplicar. La trust policy se reescribira con condition `aws:SourceArn`. Esta conversion es idempotente (no recreate el role, solo actualiza la assume_role_policy).

[cog]: https://github.com/ahincho/orion-cognitive-agent

## Contacto

- Owner: `@ahincho` (solo-dev).$
