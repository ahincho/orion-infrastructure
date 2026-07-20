# modules/iam-orion-agent-core-runtime

IAM role asssumido por el **contenedor** que corre dentro de Bedrock AgentCore
Runtime. Complementa `modules/iam-orion-agent-core-deploy` (que asume GitHub
Actions OIDC).

## Recursos que crea

| Recurso | Nombre | Proposito |
|---|---|---|
| `aws_iam_role` | `<project_name>-agent-core-runtime-<env>` | Trust en `bedrock-agentcore.amazonaws.com`, opt. con `aws:SourceArn` |
| `aws_iam_role_policy` | `<project_name>-agent-core-runtime-<env>-inline` | Permisos Bedrock InvokeModel + CloudWatch logs |

## Inputs

| Nombre | Tipo | Default | Descripcion |
|---|---|---|---|
| `project_name` | `string` | (requerido) | kebab-case, 3-30 chars. Validado. |
| `environment` | `string` | (requerido) | `dev`/`staging`/`prod`. Validado. |
| `runtime_arn` | `string` | `""` | ARN del AgentRuntime (formato `arn:aws:bedrock-agentcore:<region>:<account>:runtime/<id>`). Si proveido, agrega condition `aws:SourceArn` en trust (anti-confused-deputy estricto). Default vacio para bootstrap. |
| `tags` | `map(string)` | `{}` | Tags adicionales. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `runtime_role_arn` | ARN del IAM role. Wire como `role_arn` en el modulo `bedrock-agent-core-runtime`. Anadir a `var.agentcore_runtime_role_arns` del `iam-orion-agent-core-deploy` module para que el deploy job pueda PassRole. |
| `runtime_role_name` | Nombre del role. |
| `runtime_role_id` | ID unico interno. |

## Permisos concedidos

1. **Bedrock InvokeModel + Converse + ConverseStream** sobre `*` (acciones API-level no restrictable por recurso individual).
2. **CloudWatch Logs** sobre `/aws/bedrock-agentcore/*` log groups (`CreateLogGroup`, `CreateLogStream`, `PutLogEvents`, `Describe*`).

NO incluye:
- Acceso a S3, RDS, KMS u otros AWS services fuera del scope del runtime
  (agregar statements adicionales si se requieren en runtime modules futuros).
- IAM PassRole (lo necesita el deploy role, no el runtime execution role).

## Trust policy

Asumible SOLO por:
- `Service: bedrock-agentcore.amazonaws.com`
- Condition opcional `aws:SourceArn = <runtime_arn>` (si `var.runtime_arn != ""`).

**No** asumible por:
- Usuarios humanos (ningun `Principal: AWS` ni federated).
- Otros servicios AWS.

## Patron de uso (2 fases)

**Fase 1 (este PR)**: el role se crea con trust sin condition (var `runtime_arn = ""`). Esto permite crear primero el role, luego el AgentRuntime en el modulo `bedrock-agent-core-runtime` (PR #45), y finalmente reapuntar el role al ARN concreto.

**Fase 2 (futuro, despues de PR #45)**: una vez el AgentRuntime este creado, copiar su `arn` (output `runtime_arn` del modulo `bedrock-agent-core-runtime`) al param `runtime_arn` del este modulo en `live/dev/main.tf`, y reaplicar. La trust policy se reescribira con la condition estricta.

Alternativa (no recomendada): usar `data "aws_bedrockagentcore_agent_runtime"` en este modulo y re-aplicar tras creacion. Anadiria dependencia de bootstrap order que complica Terraform sin beneficio claro.

## Skip de Checkov

- `CKV_AWS_60/61/107/358` (trust policy) — valido para roles asssumidos por servicios AWS.
- `CKV_AWS_109/290/355/356/111` (inline policy) — el role es service-principal-only, no user-assumable.

Razon inline en `main.tf`.
