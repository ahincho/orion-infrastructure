# Module: `orion-infrastructure::eventbridge-bus`

Crea el custom EventBridge bus para ORION (`orion-events-dev`).

## Que hace

- **Custom bus** `orion-events-dev` (configurable via `bus_name`).
- **Resource-based policy**: any IAM principal in the same AWS account can `events:PutEvents` to this bus. Cross-account principals can be added later.
- **Default observability rule** (toggle): captura todos los eventos con `source` que empieza con `orion.` y los escribe a un CW Log Group (`/aws/events/orion-events-dev`, retention configurable).

## Uso

```hcl
module "eventbridge" {
  source = "../../modules/eventbridge-bus"

  project_name = "orion"
  environment  = "dev"
  bus_name     = ""  # default = orion-events-dev

  enable_default_log_rule  = true
  event_log_retention_days = 30

  tags = local.common_tags
}
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `bus_name` | `""` | Default: `${project_name}-events-${environment}`. |
| `enable_default_log_rule` | `true` | Si true, crea log group + regla base. |
| `event_log_retention_days` | `30` | Retencion CW Logs. dev=7-30; prod>=90. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `bus_name` | Nombre final del bus. |
| `bus_arn` | ARN completo (usar en IAM policies). |
| `event_log_group_name` | `/aws/events/<bus>`, o null. |
| `event_log_group_arn` | ARN del log group. |
| `events_log_writer_role_arn` | IAM role asumida por EventBridge. |
| `log_all_rule_arn` | ARN de la regla default. |

## Decisiones de diseno

- **Resource policy explicit + same-account root**: Aunque el cross-principal same-account es tecnicamente solo IAM, una resource policy explicita deja el contrato audit-grade (visible en `aws events describe-event-bus --name ... --query Policy`).
- **Default log rule ON**: Cero-config observabilidad para dev. Permite depurar el flujo de eventos sin tener que configurar Firehose/OpenSearch. Para prod se puede desactivar y configurar un sink serio.
- **`source` prefix `orion.`**: Solo eventos que vienen de bounded contexts ORION pasan al log default. EventBridge incluye un campo `source` obligatorio en cada PutEvents; aqui filtra por prefijo.
- **No archive/replay**: Cost $$$$. Deferrable. Si se necesita replay para tests de carga de consumers, se puede anadir via `modules/eventbridge-archive/` (resource: `aws_cloudwatch_event_archive`).

## Convencion de eventos ORION

El bus sigue el contrato cross-ORION (definido en AGENTS.md de orion-backend):

- **Source**: `orion.<context>` (e.g., `orion.identity`, `orion.census`).
- **Detail-type**: PascalCase past-tense (e.g., `UserCreated`, `RecordUpdated`).
- **Envelope**:
  ```json
  {
    "version": 1,
    "data": { /* event-specific payload */ }
  }
  ```
- **Bus name**: `orion-events-${Environment}`.

## Integracion esperada con otros modulos

```hcl
# modules/iam-lambda-exec/ (PR #31) — habilitar publishing
data "aws_iam_policy_document" "lambda_eb_put" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [module.eventbridge.bus_arn]
  }
}

# modules/ssm-bootstrap/ (PR #28) — exponer el ARN via SSM
resource "aws_ssm_parameter" "eb_bus_arn" {
  value = module.eventbridge.bus_arn
  # name + SecureString se configuran en el modulo ssm-bootstrap.
}
```

orion-backend runtime:
```typescript
import { EventBridgeClient, PutEventsCommand } from "@aws-sdk/client-eventbridge";

const eb = new EventBridgeClient({ region: process.env.AWS_REGION });
await eb.send(new PutEventsCommand({
  Entries: [{
    EventBusName: process.env.EVENT_BUS_NAME,        // orion-events-dev
    Source: `orion.${context}`,
    DetailType: "UserCreated",
    Detail: JSON.stringify({ version: 1, data: { ... } }),
  }],
}));
```

## Checkov skips

- `CKV_AWS_110`, `CKV2_AWS_40` (same-account root): cross-account se difiere a prod.
- `CKV_AWS_158/338/345`: CW Log Group usa AWS-managed CMK en dev.
- `CKV_AWS_61`, `CKV_AWS_60`: IAM role trust del service principal `events.amazonaws.com`.
- `CKV_AWS_356`, `CKV_AWS_290`: events.amazonaws.com PutEvents a log group ARN.
