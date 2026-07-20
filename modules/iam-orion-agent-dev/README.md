# Module: iam-orion-agent-dev

Crea el IAM role + inline policy `OrionAgentDeployPolicy` que asume el futuro
workflow `CD - Deploy` de **orion-cognitive-agent** via GitHub OIDC.

El workflow de deploy corre en `ahincho/orion-cognitive-agent` y necesita
permisos para:

1. **ECR push** — `ecr:PutImage`, `ecr:InitiateLayerUpload`,
   `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, plus
   `ecr:GetAuthorizationToken` (account-level). Resource scoped a
   `arn:aws:ecr:<region>:<account>:repository/orion-agent` y `/*`.
2. **Bedrock InvokeModel** — para smoke tests inline en el deploy workflow.
   Cross-region inference profile ID es parametrizable (`bedrock_model_id`,
   default `us.anthropic.claude-sonnet-4-20250514`).
3. **Bedrock AgentCore** management completo del Runtime (create/update/delete
   del Runtime + endpoints + InvokeAgentRuntime). El modulo
   `bedrock-agentcore-runtime` proporsionara el ARN-scoped cuando se cree
   el recurso en Sprint B.2.
4. **CloudWatch Logs** del runtime (`/aws/orion/agent/dev/*`,
   `/aws/bedrock-agentcore/*`).
5. **SSM** read `/orion/agent/*` (cors, secrets ARNs, runtime config).
6. **IAM PassRole** al servicio `bedrock-agentcore.amazonaws.com` (limita
   confused-deputy: el role solo puede pasarse a AgentCore, no a otros
   servicios AWS). Resource scoped a `orion-agent-exec-*` (será creado
   por el modulo `bedrock-agentcore-runtime` en Sprint B.2).

## Trust policy

- OIDC issuer: `arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com`
  (asume que el OIDC provider ya existe, creado por `modules/oidc-github`).
- Audience: `sts.amazonaws.com`.
- Subject: `repo:ahincho/orion-cognitive-agent:ref:refs/heads/main`
  y `repo:ahincho/orion-cognitive-agent:environment:<env>` (env
  parametrizable via `github_environments`).

## Uso

```hcl
module "iam_orion_agent_dev" {
  source = "../modules/iam-orion-agent-dev"

  project_name = "orion"
  environment  = "dev"
  aws_region   = "us-east-1"
  account_id   = "681526276858"

  github_org          = "ahincho"
  github_repo         = "orion-cognitive-agent"
  github_branch       = "refs/heads/main"
  github_environments = ["dev"]

  ecr_repository_name = "orion-agent"
  bedrock_model_id    = "us.anthropic.claude-sonnet-4-20250514"
}
```

## Outputs

- `role_arn` — usar como `AWS_DEPLOY_ROLE_ARN` en el GH Environment `dev`
  de orion-cognitive-agent.
- `role_name` — `orion-agent-deploy-dev` (literal).
- `policy_name` — `OrionAgentDeployPolicy` (inline, 7 statements).

## Notas

- El role NO recrea el OIDC provider; asume que `modules/oidc-github`
  se aplicó primero (Phase 0).
- `default_tags` (Project, Environment, ManagedBy, Repository) se aplican
  via `live/dev/providers.tf` (definido en el caller, no en este modulo).
- Pendiente para Sprint B.2: cross-reference con el ARN del futuro
  Runtime (mover las acciones `bedrock-agentcore:*` de `Resource = "*"`
  a ARN-scoped explicit cuando el recurso esté creado).
- Pendiente para Sprint C: cuando se cree `modules/iam-orion-agent-exec-dev`
  (execution role del container en runtime), ajustar el pattern
  `orion-agent-exec-*` en la statement `IAMPassRoleToBedrockAgentCore`.
