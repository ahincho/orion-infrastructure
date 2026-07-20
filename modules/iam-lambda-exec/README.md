# Module: `orion-infrastructure::iam-lambda-exec`

Crea el IAM execution role para las funciones Lambda de orion-backend, junto con el security group dedicado.

## Que hace

- **`aws_iam_role`** `orion-<env>-lambda-exec-` (prefix) con trust policy: `lambda.amazonaws.com`.
- **3 managed policies**:
  - `AWSLambdaBasicExecutionRole` (CW Logs).
  - `AWSLambdaVPCAccessExecutionRole` (ENI creation/describing para VPC Lambda).
  - `AWSLambdaTracingExecutionRole` (X-Ray write; Powertools Tracing Active).
- **1 inline policy condicional** (solo si al menos 1 input ARNs esta populated):
  - `secretsmanager:GetSecretValue`/`DescribeSecret` sobre `var.secret_arns`.
  - `ssm:GetParameter`/`GetParameters` sobre `var.ssm_parameter_arns`.
  - `events:PutEvents` sobre `var.eventbridge_bus_arn`.
  - `rds-db:connect` sobre `var.rds_db_resource_arn` (IAM auth enabled).
- **`aws_security_group`** con egress scope a VPC CIDR. Ingress vacio intencionalmente (Lambda se invoca via IAM, no via network).

## Uso

```hcl
module "iam_lambda_exec" {
  source = "../../modules/iam-lambda-exec"

  project_name = "orion"
  environment  = "dev"

  vpc_id = module.network.vpc_id
  vpc_cidr = "10.20.0.0/16"

  # Cross-module wiring (orquestador PR #32):
  secret_arns = [
    module.secrets.jwt_signing_secret_arn,
    module.rds.master_user_secret_arn,
  ]

  ssm_parameter_arns = [
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/orion/secret/jwt-arn",
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/orion/db/secret-arn",
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/orion/eventbridge/bus-arn",
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/orion/cors/allowed-origins",
  ]

  eventbridge_bus_arn = module.eventbridge.bus_arn
  rds_db_resource_arn = "arn:aws:rds-db:us-east-1:681526276858:dbname:${module.rds.resource_id}/orion"

  tags = local.common_tags
}
```

orion-backend template.yaml lo consume como:
```yaml
Globals:
  Function:
    Role: '{{resolve:ssm:/orion/lambda/role-arn}}'  # futuro param SSM
    VpcConfig:
      SecurityGroupIds: [!GetAtt LambdaSecurityGroup]
      SubnetIds: <private_subnet_ids>
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `secret_arns` | `[]` | ARNs de Secrets Manager (JWT + RDS). |
| `ssm_parameter_arns` | `[]` | ARNs de SSM Parameters (4 paths). |
| `eventbridge_bus_arn` | `""` | ARN del bus EventBridge. Vacio = no crear permission. |
| `rds_db_resource_arn` | `""` | RDS resource ARN para IAM auth. Vacio = no crear permission. |
| `vpc_id` | requerido | VPC donde se crea el SG. |
| `vpc_cidr` | `10.20.0.0/16` | CIDR del VPC para scope egress del SG. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `role_arn` | ARN del IAM role (usar como Lambda `Role`). |
| `role_name`, `role_unique_id` | Identificadores. |
| `lambda_security_group_id` | SG ID (referenciar desde RDS ingress allowlist). |
| `managed_policies_attached` | ARNs de los 3 managed policies. |
| `inline_policy_name` | Nombre del inline policy (Secrets+SSM+EB+RDS). |

## Decisiones de diseno

- **3 managed policies (no inline-only)**: las 3 managed policies oficiales son mas mantenibles y audit-grade que recrear equivalentes inline.
- **Conditional inline policy**: si ninguna lista/ARN esta populated, no se crea el inline policy (zero-cost zero-noise).
- **SG ingress vacio**: el Lambda service no necesita ingress para invocar; el IAM role authorize. Mantenerlo vacio es seguro y minimiza superficie de ataque.
- **Egress scope a VPC CIDR**: las Lambdas hablan a RDS (5432) + VPC endpoints (S3/SM/Logs/SSM/EB/ECR) + NAT (si fuera necesario para egress externo). Cero egress a internet publico por defecto.
- **Trust policy sin condiciones**: para dev. Prod deberia aniadir `aws:SourceAccount = <this-account>` para evitar confusion attacks (otro AWS account impersonando Lambda via esta role).

## Checkov skips

- `CKV_AWS_60`, `CKV_AWS_61`: trust limited to service principal.
- `CKV_AWS_107/108/109/110`: actions especificas, no privilege escalation.
- `CKV_AWS_111`, `CKV_AWS_356`, `CKV_AWS_290`: actions especificas, resources scope-restricted.
- `CKV_AWS_24/260/277`: Lambda SG ingress vacio intencional.
- `CKV_AWS_382`: egress scope-restricted a VPC CIDR (no 0.0.0.0/0 all).

## Diferencias para prod (futuro)

- Aniadir condicion `aws:SourceAccount` al trust policy.
- Activar `monitoring_interval=60` en el RDS para enhanced monitoring.
- Activar PI retention long-term en el RDS.
- KMS CMK explicito para SM/SSM encryption.
