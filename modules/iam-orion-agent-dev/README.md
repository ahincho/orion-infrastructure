# modules/iam-orion-agent-dev

IAM role OIDC-asumible por GitHub Actions del repo
[`ahincho/orion-cognitive-agent`][1] para deploys del runtime de
Bedrock AgentCore.

[1]: https://github.com/ahincho/orion-cognitive-agent

## Recursos que crea

| Recurso | Nombre | Proposito |
|---|---|---|
| `aws_iam_role` | `<project_name>-agent-deploy-<env>` | Trust OIDC con `repo:ahincho/orion-cognitive-agent:ref:refs/heads/main` |
| `aws_iam_role_policy` | `<project_name>-agent-deploy-<env>-inline` | Permisos granulares para el deploy del AgentCore Runtime |

## Inputs

| Nombre | Tipo | Default | Descripcion |
|---|---|---|---|
| `project_name` | `string` | (requerido) | kebab-case, 3-30 chars. Validado. |
| `environment` | `string` | (requerido) | `dev`/`staging`/`prod`. Validado. |
| `github_repository` | `string` | (requerido) | Formato `owner/repo`. Confiar en `token.actions.githubusercontent.com:sub`. |
| `oidc_provider_arn` | `string` | (requerido) | `module.oidc_github.oidc_provider_arn`. |
| `ecr_repository_arn` | `string` | (requerido) | `module.ecr_orion_agent.repository_arn`. |
| `agentcore_runtime_role_arns` | `list(string)` | `[]` | ARNs de Runtime roles (opcional, para `iam:PassRole`). |
| `tags` | `map(string)` | `{}` | Tags adicionales. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `deploy_role_arn` | ARN del IAM role. Wire a GitHub Secret `AGENT_DEPLOY_ROLE_ARN`. |
| `deploy_role_name` | Nombre del role. |
| `deploy_role_id` | ID unico interno. |

## Permisos concedidos

1. **ECR pull + auth** sobre el repo `orion-agent-<env>`.
2. **Bedrock AgentCore Runtime** (control + data plane, incluye Code Interpreter + Browser si necesarios).
3. **Bedrock InvokeModel / Converse** (inference en runtime).
4. **CloudWatch Logs** sobre `/aws/bedrock-agentcore/*`.
5. **SSM Parameters** `/orion/agent/runtime-arn` + `/orion/agent/endpoint-arn` (lectura).
6. **IAM PassRole** opcional hacia `bedrock-agentcore.amazonaws.com` (solo si el caller provee `agentcore_runtime_role_arns`).

## Trust policy

Asumible SOLO por:

- `token.actions.githubusercontent.com:aud == sts.amazonaws.com`
- `token.actions.githubusercontent.com:sub == repo:ahincho/orion-cognitive-agent:ref:refs/heads/main`

No requiere `sts:ExternalValidation` (CKV_AWS_107) ni cross-account: GitHub
OIDC es la unica fuente de tokens validos para este role.

## Skip de Checkov

- `CKV_AWS_60/61/107/358` (trust policy) — valido para roles OIDC; los
  checks estan pensados para roles asumibles por humanos / IAM users.
- `CKV_AWS_109/290/355/356/111` (inline policy) — el role esta restringido al
  OIDC main branch; los checks requieren condiciones adicionales que no
  aplican a flujos OIDC-only.

Razon de cada skip inline con `#checkov:skip=ID:reason` en `main.tf`.
