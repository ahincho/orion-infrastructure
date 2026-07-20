# Module: `orion-infrastructure::network`

Crea el **data plane de red** para un entorno ORION (AWS): VPC con subnets
publicas/privadas, NAT Gateway, IGW, route tables, VPC flow logs y un
set configurable de **VPC endpoints** (S3 gateway + interface endpoints
para Secrets Manager, CloudWatch Logs, SSM, EventBridge y ECR).

## Uso

```hcl
module "network" {
  source = "../../modules/network"

  project_name = "orion"
  environment  = "dev"
  vpc_cidr     = "10.20.0.0/16"

  # 2 AZs en us-east-1; se usan las primeras N del data source si no se
  # pasan explicitamente.
  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

  single_nat_gateway   = true  # 1 NAT compartido (ahorra ~$32/mes/AZ)
  enable_vpc_endpoints = true  # ahorra NAT egress a AWS APIs

  vpc_endpoint_services = [
    "secretsmanager",   # Secrets Manager
    "logs",             # CloudWatch Logs
    "ssm",              # Parameter Store
    "events",           # EventBridge
    "ecr.api",          # ECR API
    "ecr.dkr",          # ECR Docker Registry
  ]

  tags = local.common_tags
}
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | prefijo kebab-case (3-30 chars). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `vpc_cidr` | `10.20.0.0/16` | CIDR IPv4 del VPC. |
| `azs` | `[]` | Lista explicita de AZs. Si vacia, se toman las primeras N segun `public_subnet_cidrs`. |
| `public_subnet_cidrs` | `["10.20.0.0/24","10.20.1.0/24"]` | 1 CIDR por AZ. |
| `private_subnet_cidrs` | `["10.20.10.0/24","10.20.11.0/24"]` | Mismo length que public. |
| `single_nat_gateway` | `true` | `true` = 1 NAT compartido (recomendado dev). `false` = 1 NAT/AZ. |
| `enable_vpc_endpoints` | `true` | Toggle para todos los endpoints. |
| `vpc_endpoint_services` | ver arriba | Servicios para Interface endpoints. |
| `flow_log_retention_days` | `30` | Retencion CW Logs. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Tipo | Descripcion |
|---|---|---|
| `vpc_id` | string | ID del VPC. |
| `vpc_cidr` | string | CIDR block. |
| `vpc_arn` | string | ARN del VPC. |
| `public_subnet_ids` | list(string) | IDs subnets publicas (ordenadas por AZ). |
| `private_subnet_ids` | list(string) | IDs subnets privadas (ordenadas por AZ). |
| `public_subnet_cidrs` | list(string) | CIDRs subnets publicas. |
| `private_subnet_cidrs` | list(string) | CIDRs subnets privadas. |
| `private_route_table_ids` | list(string) | IDs route tables privadas. |
| `vpc_endpoint_security_group_id` | string | SG de Interface endpoints. |
| `s3_vpc_endpoint_id` | string | ID del S3 Gateway endpoint. |
| `flow_log_id` | string | ID del VPC flow log. |
| `azs` | list(string) | AZs resueltas. |
| `nat_gateway_public_ips` | list(string) | EIPs de los NAT Gateways. |

## Wiring tipico con otros modulos

```hcl
module "iam_lambda_exec" {
  source = "../iam-lambda-exec"
  # ...
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  vpc_endpoint_sg_id     = module.network.vpc_endpoint_security_group_id
}

module "rds" {
  source = "../rds-postgres"
  # ...
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
}
```

## Decisiones de diseno

- **Single NAT por default** porque para dev el coste (~32 USD/mes/AZ extra) no aporta
  valor; en prod se cambia a `single_nat_gateway = false` para mantener alta
  disponibilidad ante AZ failures.
- **VPC endpoints** incluido por defecto para los servicios que toca el
  runtime de Lambda + RDS (Secrets Manager, CW Logs, SSM, EventBridge, ECR)
  para evitar NAT egress a AWS APIs (`$0.045/GB`).
- **Flow logs a CW** + IAM role dedicado. Retention default 30d; ajustable
  segun entorno.
- **Default SG sin reglas**: el modulo nunca toca el SG por defecto de AWS.
  Los recursos que necesitan ingress deben declarar su propio SG (pej.
  RDS, Lambda).
- **DNS support + hostnames** habilitados para que los VPC endpoints
  interface con `private_dns_enabled = true` resuelvan al IP privado
  (sin necesidad de editar `/etc/resolv.conf`).

## Saltarse checks de checkov

Varias reglas de checkov (`CKV_AWS_*`) requieren annotaciones in-line porque
la intencion del diseno no encaja con la regla por defecto. Cada skip tiene
comentario `# checkov:skip=CKV_...: <razon>` adyacente.
