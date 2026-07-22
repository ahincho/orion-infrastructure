# Module: `orion-infrastructure::seed-users`

Aprovisiona la infraestructura necesaria para sembrar usuarios iniciales
(advisors, supervisors, agents) en `identity.users` desde Lambda.

## Recursos creados

| Recurso | Tipo | Default / Formato |
|---|---|---|
| `<project>-<env>-shared-dev-password` | `aws_secretsmanager_secret` | SecureString, JSON `{version, use, password, rotatedAt}` |
| `<id de la version inicial>` | `aws_secretsmanager_secret_version` | Lifecycle ignore_changes |
| `/orion/seed/email-domain` | `aws_ssm_parameter` | SecureString, default `orion.dev` |
| `<project>-seed-users-lambda-exec-<env>` | `aws_iam_role` | Lambda execution role (trust `lambda.amazonaws.com`) |
| `SeedUsersLambdaExecPolicy` | `aws_iam_role_policy` (inline) | Permisos scoped |

## Outputs clave (consumidos por Stage 6 `orion-backend`)

| Output | Consumer | Uso |
|---|---|---|
| `shared_dev_password_secret_arn` | bootstrap-supervisor + seed-users Lambda env vars | SM GetSecretValue para password |
| `email_domain_ssm_param_name` | `{{resolve:ssm:/orion/seed/email-domain}}` en template.yaml | Email construction |
| `lambda_exec_role_arn` | `Role:` en `AWS::Serverless::Function` | Lambda execution role |

## Uso en `live/dev/main.tf`

```hcl
module "seed_users" {
  source = "../../modules/seed-users"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  rds_app_connection_secret_arn = module.rds_postgres.app_connection_secret_arn

  # Defaults explicitos para dev:
  email_domain               = "orion.dev"
  shared_password_length     = 32
  recovery_window_in_days    = 0

  tags = local.common_tags
}
```

## Decisiones de diseno

- **Shared dev password (NO production-ready)**: explicito y conscious para
  dev. Un solo valor random se genera via `random_password`. Todos los
  usuarios seed usan este mismo password hasheado con scrypt (la Lambda
  lo hashea antes de insertar). Para prod: modulo `secrets-rotation/` con
  password unico por usuario + rotation automatica (no incluido en este
  scope).

- **Lambda execution role dedicado** (no reutiliza `module.iam_lambda_exec`)
  para evitar over-permissioning. Las Lambdas seed-users solo necesitan:
  - SM GetSecretValue sobre 2 secretos especificos (shared password + RDS).
  - SSM GetParameter sobre `/orion/seed/email-domain`.
  - EC2 ENI management para VPC attachment.
  - CW Logs + X-Ray + KMS Decrypt (scoped a Project=orion tags).

- **`email_domain` como SSM SecureString** (no plano) para homogenizar
  el patron de consumption con `/orion/cors/allowed-origins` y
  `/orion/secret/jwt-arn`.

- **VPC inputs requeridos**: omitidos del modulo en este PR (no se usan
  en la trust/policy actual). Si las Lambdas seed-users en el futuro
  necesitan VPC inputs (subnets + SG IDs), agregarlos como variables
  requeridas.

- **Trust policy solo service principal**: si en el futuro se quiere
  tightens con `aws:SourceArn`, copiar el ARN especifico de cada Lambda
  bootstrap-supervisor / seed-users creada y agregarlo como condition
  (post-deploy, patron identico a `iam-orion-agent-core-runtime` 2-fases
  bootstrap documentado en AGENTS.md).

## Stage 4 -> Stage 5/6 wire

1. Stage 4 (este PR): crear el modulo + apply.
2. Stage 5: 4 reusable workflows en `spark-match-01-devops`:
   - `aws-lambda-invoke.yml` (generic wrapper).
   - `seed-users-{advisors,supervisors,agents}.yml` (wrappers especificos
     que invocan la Lambda seed-users con el grupo de usuarios correspondiente).
3. Stage 6: 2 Lambdas en `orion-backend`:
   - `bootstrap-supervisor.ts`: crea el primer supervisor (admin) usando el
     shared password. Idempotente (check si existe antes de insert).
   - `seed-users.ts`: crea N advisors + M supervisors + K agents con
     emails deterministas (`<role>-<NNN>@<email_domain>`). Idempotente.

## Tags

Todos los recursos llevan tags: `Project`, `Environment`, `ManagedBy`,
`Repository`, `Module` (via `local.common_tags` + tag `Name`).