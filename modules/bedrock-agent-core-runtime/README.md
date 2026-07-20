# modules/bedrock-agent-core-runtime

Provisiona un [Bedrock AgentCore Runtime][1] + un Endpoint (alias) para
ejecutar OrionAgentCore (deep agent basado en `langchain-aws`).

[1]: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agents.html

## Recursos que crea

| Recurso | Nombre AWS | Proposito |
|---|---|---|
| `aws_bedrockagentcore_agent_runtime` | `orion_agent_core_dev` | El runtime (host del contenedor). |
| `aws_bedrockagentcore_agent_runtime_endpoint` | `orion_agent_core_dev/dev` | Alias para invocaciones. |

## Inputs

| Nombre | Tipo | Default | Descripcion |
|---|---|---|---|
| `project_name` | `string` | (requerido) | kebab-case, 3-30 chars. Validado. |
| `environment` | `string` | (requerido) | `dev`/`staging`/`prod`. Validado. |
| `agent_runtime_name` | `string` | `"orion_agent_core_dev"` | Nombre del Runtime. **Restriccion AWS**: `^[a-zA-Z][a-zA-Z0-9_]{0,47}$` (sin guiones). |
| `container_uri` | `string` | (requerido) | ECR URI del container (e.g. `<acct>.dkr.ecr.us-east-1.amazonaws.com/orion-agent-core-dev:<tag>`). |
| `role_arn` | `string` | (requerido) | ARN del IAM Role execution (`module.iam_orion_agent_core_runtime.runtime_role_arn`). |
| `network_mode` | `string` | `"PUBLIC"` | `PUBLIC` o `VPC`. |
| `subnets` | `list(string)` | `[]` | Subnet IDs (solo si `network_mode='VPC'`). |
| `security_groups` | `list(string)` | `[]` | SG IDs (solo si `network_mode='VPC'`). |
| `environment_variables` | `map(string)` | `{}` | Env vars pasadas al contenedor. |
| `description` | `string` | (default) | Descripcion libre (max 4096 chars). |
| `endpoint_name` | `string` | `"dev"` | Nombre del endpoint (alias). |
| `endpoint_description` | `string` | (default) | Descripcion del endpoint (max 256 chars). |
| `tags` | `map(string)` | `{}` | Tags adicionales. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `agent_runtime_id` | ID opaco del Runtime. |
| `agent_runtime_arn` | ARN del Runtime. **Copiar este valor** al param `runtime_arn` del modulo `iam-orion-agent-core-runtime` (PR #44, fase 2 bootstrap) para tightens la trust policy con `aws:SourceArn`. |
| `agent_runtime_version` | Version del Runtime (incrementa por UpdateAgentRuntime). |
| `endpoint_arn` | ARN del Endpoint. URL SigV4: `https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/<endpoint_arn>/invocations`. |
| `endpoint_id` | ID del Endpoint. |
| `endpoint_name` | Nombre del alias. |

## Invocacion (data plane)

El endpoint se invoca con SigV4 (no hay API keys). Flujo desde una app externa
(Lambda, EC2, ECS Task, local con creds AWS):

```
POST /runtimes/<endpoint_arn>/invocations
Content-Type: application/json
Authorization: AWS4-HMAC-SHA256 Credential=<access_key>/20261001/us-east-1/bedrock-agentcore/aws4_request,...

{
  "input": { "text": "What is the weather today?" },
  "sessionId": "optional-session-id"
}
```

## Container entrypoint contract

El contenedor que se publica en ECR DEBE responder a:

- `GET /ping` (health check de AgentCore) -> `200 OK` con body libre.
- `POST /invocations` (entry point principal) -> ejecuta `agent.invoke(input)`
  y devuelve el output en JSON.

Variables de entorno que AgentCore auto-pasa al contenedor ademas de las que
declaremos en `environment_variables`:

- `BEDROCK_AGENTCORE_RUNTIME_ARN`, `BEDROCK_AGENTCORE_ENDPOINT_ARN`,
  `BEDROCK_AGENTCORE_AGENT_ID`, `AWS_REGION`, etc. (ver docs AWS).

## Lifecycle

- `agent_runtime_name` cambio = recreate (stringplanmodifier.RequiresReplace).
- Cambiar `container_uri` u `environment_variables` = update (no recreate).
- Cambiar `role_arn` = update.
- Cambiar `network_mode` PUBLIC -> VPC = update; VPC -> PUBLIC = update pero
  requiere remover `network_mode_config` primero.
- `agent_runtime_version` se autoincrementa con cada Update efectivo.

## Skip de Checkov (esperado)

- `CKV_AWS_*` no suelen aplicar a recursos de servicio (AgentCore Runtime no es
  recurso de IAM/S3/etc.). Si checkov marca alguna, documentar en el
  resource block con `# checkov:skip=`.

## Decisiones futuras

- **VPC mode**: si OrionAgentCore necesita acceso a RDS privado, cambiar a
  `network_mode='VPC'` y pasar `module.network.private_subnet_ids` +
  `module.network.<agent_sg_id>` (crear SG en `modules/network` o nuevo
  modulo `iam-orion-agent-core-runtime-sg`).
- **Memory**: si el agente necesita memoria larga, anadir recurso
  `aws_bedrockagentcore_memory` y conectar via `agent_runtime_artifact` /
  `lifecycle_configuration` (PR #47).
- **Policy Engine (Cedar policies)**: para defense-in-depth contra prompt
  injection, anadir `aws_bedrockagentcore_policy_engine` (PR #49).
