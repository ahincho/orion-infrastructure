# Module: `orion-infrastructure::rds-postgres`

Crea una instancia RDS Postgres para ORION. Configuracion default compatible con **AWS Free Tier** (`db.t4g.micro`, 20 GB, single-AZ, Postgres 17).

## Que hace

- **`aws_db_subnet_group`** con las subnet privadas del VPC (típicamente `modules/network.private_subnet_ids`).
- **`aws_security_group`** con ingress TCP/5432 desde los SGs allowlist (típicamente el SG de las Lambdas).
- **`aws_db_parameter_group`** (Postgres 17 family) con tuning: `log_statement=all`, `log_min_duration_statement=1000`, `shared_buffers=16MB`, `max_connections=100`, `work_mem=4MB`, `timezone=UTC`.
- **`aws_db_instance`** con `manage_master_user_password=true` (RDS manages password via Secrets Manager; rotation enableable).

## Decisiones de diseno (vs Aurora Serverless v2)

- **Free tier no cubre Aurora**. Usamos RDS Postgres standard (`aws_db_instance`).
- **Engine 17.10** default (latest estable en us-east-1; soporta muchas features modernas, RDS 17).
- **`db.t4g.micro`** default (ARM Graviton; free-tier eligible; mejor perf/watt que db.t3.micro).
- **20 GB gp3** = max free-tier storage. `storage_encrypted=true` (sin coste extra para gp3).
- **Multi-AZ OFF** por free-tier; `availability_zone=us-east-1a` explicito.
- **Performance Insights OFF** por defecto (7 dias gratis; >7 cuesta).
- **Deletion protection OFF** para permitir `terraform destroy` en dev.

## Uso

```hcl
module "rds" {
  source = "../../modules/rds-postgres"

  project_name = "orion"
  environment  = "dev"

  engine_version  = "17.10"
  instance_class  = "db.t4g.micro"  # free-tier
  allocated_storage = 20

  # Network (de modules/network):
  vpc_id        = module.network.vpc_id
  db_subnet_ids = module.network.private_subnet_ids

  # SG allowlist (de modules/iam-lambda-exec o composer):
  allowed_security_group_ids = [
    module.iam_lambda_exec.lambda_security_group_id,
  ]

  multi_az = false   # free-tier
}
```

Produccion (multi-AZ, mayor instance class):

```hcl
module "rds_prod" {
  source = "../../modules/rds-postgres"
  project_name = "orion"
  environment  = "prod"

  instance_class    = "db.t4g.small"
  allocated_storage = 100
  multi_az          = true
  backup_retention_period = 14

  kms_key_id = module.kms.postgres_cmk_arn
  master_user_secret_kms_key_id = module.kms.postgres_cmk_arn

  vpc_id        = module.network_prod.vpc_id
  db_subnet_ids = module.network_prod.private_subnet_ids
  allowed_security_group_ids = [
    module.iam_lambda_exec_prod.lambda_security_group_id,
  ]
}
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `engine_version` | `17.10` | Postgres version. |
| `instance_class` | `db.t4g.micro` | Free-tier eligible: `db.t3.micro`, `db.t4g.micro`, `db.t3.small`, `db.t4g.small`. |
| `allocated_storage` | `20` | Storage inicial GB (max free-tier). |
| `max_allocated_storage` | `100` | Autoscaling cap. 0 desactiva. |
| `storage_type` | `gp3` | `gp2` o `gp3`. |
| `storage_encrypted` | `true` | at-rest encryption. |
| `kms_key_id` | `""` | KMS CMK storage encryption. Vacio = AWS-managed. |
| `database_name` | `orion` | DB inicial. |
| `master_username` | `orion_admin` | Master user. Password via RDS-managed Secrets Manager. |
| `manage_master_user_password` | `true` | RDS genera password en Secrets Manager. |
| `master_user_secret_kms_key_id` | `""` | KMS CMK para el master secret. |
| `multi_az` | `false` | Multi-AZ (HA). dev=false (free-tier); prod=true. |
| `publicly_accessible` | `false` | **Nunca true**. |
| `vpc_id` | requerido | VPC ID (modules/network). |
| `db_subnet_ids` | requerido | List de subnet IDs privadas. |
| `allowed_security_group_ids` | `[]` | SGs allowlist para ingress 5432. |
| `backup_retention_period` | `1` | Dias. dev=1-7 (free max); prod>=14. |
| `preferred_backup_window` | `03:00-04:00` | UTC. |
| `preferred_maintenance_window` | `Sun:04:00-Sun:05:00` | UTC. |
| `auto_minor_version_upgrade` | `true` | Auto minor upgrades. |
| `allow_major_version_upgrade` | `false` | Permitir major version upgrades in-place (16.x -> 17.x). Default false; toggle true para bumps planeados. |
| `deletion_protection` | `false` | Bloquea delete. dev=false. |
| `performance_insights_enabled` | `false` | dev=false (free up to 7d); prod=true. |
| `performance_insights_retention` | `7` | 7 (free) o 731 (long-term). |
| `monitoring_interval` | `0` | 0=disabled; 60=prod-grade. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `instance_id`, `instance_arn`, `instance_resource_id` | Identificadores. |
| `endpoint` | `host:port` (usar como DATABASE_URL). |
| `hostname`, `port` | Por separado. |
| `database_name`, `master_username` | Credeciales (sin password). |
| `master_user_secret_arn` | ARN del Secrets Manager secret con la password. |
| `security_group_id`, `db_subnet_group_name` | Wiring. |
| `engine_version_actual`, `multi_az`, `backup_retention_period` | Estado post-apply. |

## Integracion esperada con otros modulos

```hcl
# modules/iam-lambda-exec/ (PR #31) — dar acceso a las Lambdas
data "aws_iam_policy_document" "lambda_rds_connect" {
  statement {
    actions = [
      "rds-db:connect",  # IAM DB Auth (alternativa a password RDS)
    ]
    # Para password-based connection via SecretsManager, las Lambdas ya tienen
    # secretsmanager:GetSecretValue (de su IAM role).
  }
}

# modules/ssm-bootstrap/ (PR #28) — exponer endpoint + secret ARN via SSM
resource "aws_ssm_parameter" "rds_endpoint" {
  name  = "/orion/db/endpoint"
  type  = "SecureString"
  value = "${module.rds.endpoint}/${module.rds.database_name}"
}

# Orquestador (PR #32):
module "ssm_bootstrap" {
  ...
  db_secret_arn = module.rds.master_user_secret_arn
}
```

orion-backend (template.yaml) lo consume como:
```yaml
DB_SECRET_ARN: '{{resolve:ssm:/orion/db/secret-arn}}'
# + DATABASE_URL via SecretsManager.GetSecretValue en runtime Lambda.
```

## Checkov skips

- `CKV_AWS_157`: Multi-AZ=false para free-tier single AZ (dev).
- `CKV_AWS_354`: publicly_accessible=false explicito (no requiere regla).
- `CKV_AWS_133`: backup_retention_period=1 cumple minimo; subir a 7 es free-tier max.
- `CKV_AWS_118`: Enhanced monitoring deshabilitado por coste (dev).
- `CKV_AWS_24`, `CKV_AWS_260`, `CKV_AWS_277`: estos checks son para VPC endpoint SGs, no RDS SG. Placeholder.
