# Module: `orion-infrastructure::ssm-bootstrap`

Crea los SSM Parameters cross-ORION que `orion-backend` consume via
`{{resolve:ssm:/orion/...}}` en su `template.yaml`.

## Que hace

- `/orion/secret/jwt-arn` — ARN del JWT signing secret (de `modules/secrets-bootstrap/`).
- `/orion/db/secret-arn` — ARN del RDS master secret (de `modules/rds-postgres/` via `manage_master_user_password`).
- `/orion/eventbridge/bus-arn` — ARN del bus EventBridge (de `modules/eventbridge-bus/`).
- `/orion/cors/allowed-origins` — JSON list de origins CORS (default `["http://localhost:3000"]`).

## Uso

```hcl
module "ssm_bootstrap" {
  source = "../../modules/ssm-bootstrap"

  project_name = "orion"
  environment  = "dev"

  # Cross-module wiring (el orquestador pasa los ARNs reales):
  jwt_secret_arn       = module.secrets.jwt_signing_secret_arn
  db_secret_arn        = module.rds.master_secret_arn
  eventbridge_bus_arn  = module.eventbridge.bus_arn
  cors_allowed_origins = ["http://localhost:3000", "https://orion.local"]

  tags = local.common_tags
}
```

Standalone (sin orquestador), solo se crea el param CORS:

```hcl
module "ssm_bootstrap" {
  source = "../../modules/ssm-bootstrap"
  project_name = "orion"
  environment  = "dev"
  # ARN vars vacios por default = solo CORS param se crea.
}
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `jwt_secret_arn` | `""` | ARN del JWT secret. Vacio = no crear param. |
| `db_secret_arn` | `""` | ARN del RDS master secret. Vacio = no crear. |
| `eventbridge_bus_arn` | `""` | ARN del bus. Vacio = no crear. |
| `cors_allowed_origins` | `["http://localhost:3000"]` | Lista de origins. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Tipo | Descripcion |
|---|---|---|
| `jwt_secret_arn_ssm_param_name` | string | Path del param, o null. |
| `db_secret_arn_ssm_param_name` | string | Path del param, o null. |
| `eventbridge_bus_arn_ssm_param_name` | string | Path del param, o null. |
| `cors_allowed_origins_ssm_param_name` | string | Path del param (siempre creado). |
| `cors_allowed_origins_value` | string | JSON-encoded value. |
| `created_parameter_names` | list | Paths efectivamente creados. |

## Decisiones de diseno

- **Inputs opcionales + `count = 0`**: el modulo se puede aplicar
  standalone sin depender del orquestador (solo crea el CORS param).
  Cuando el orquestador pasa los ARNs, los demas params se crean.
- **`type = "String"`** (no `SecureString`): los valores son ARNs
  publicos en AWS (no son secretos). KMS encryption del SSM param
  value se difiere al futuro `modules/kms/` para prod.
- **CORS como JSON list**: SSM solo soporta strings. JSON-encoded
  para consumir directo via `JSON.parse` en el runtime Lambda.
- **No `kms_key_id`**: AWS-managed CMK por defecto. Para prod se
  subministrara explicito via `modules/kms/`.

## Integracion esperada con otros modulos ORION

```hcl
# modules/iam-lambda-exec/ (PR #31) — habilitar lectura de SSM
data "aws_iam_policy_document" "lambda_ssm_read" {
  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      module.ssm_bootstrap.jwt_secret_arn_ssm_param_name,
      module.ssm_bootstrap.db_secret_arn_ssm_param_name,
      module.ssm_bootstrap.eventbridge_bus_arn_ssm_param_name,
      module.ssm_bootstrap.cors_allowed_origins_ssm_param_name,
    ]
  }
}
```

orion-backend (template.yaml) lo consume como:
```yaml
JWT_SECRET_ARN: '{{resolve:ssm:/orion/secret/jwt-arn}}'
DB_SECRET_ARN:  '{{resolve:ssm:/orion/db/secret-arn}}'
EVENT_BUS_ARN:  '{{resolve:ssm:/orion/eventbridge/bus-arn}}'
CORS_ORIGINS:   '{{resolve:ssm:/orion/cors/allowed-origins}}'
```

## Checkov skips

- `CKV_AWS_173`: AWS-managed KMS para SSM SecureString (no aplica a String type).
- `CKV_AWS_338`: check solo aplica a CloudWatch Log Groups, no a SSM.
- `CKV2_AWS_34`: permisos finos via IAM `ResourceTags` se difieren a prod.
