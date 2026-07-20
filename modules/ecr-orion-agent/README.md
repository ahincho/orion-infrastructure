# Module: ecr-orion-agent

Repositorio ECR (Elastic Container Registry) para la imagen Docker del
cognitive agent. La imagen se pushea desde el workflow `CD - Deploy` de
orion-cognitive-agent y es luego consumida por Bedrock AgentCore Runtime
(modulo `bedrock-agentcore-runtime`, Sprint B.2).

## Configuracion

- **Tag immutability** = `IMMUTABLE` (recomendado AWS). Previene
  overwrite de tags en uso; rollback seguro garantizado.
- **Scan on push** = `true` (CVE scanning automatic al push).
- **Encryption** = AES256 (SSE-S3). KMS se omite para zero-cost en dev
  (mismo trade-off que `modules/storage-tfstate`).
- **Lifecycle**: cap a `max_image_count` (default 30); al pushear la N+1,
  AWS borra la mas antigua automaticamente.

## Resource-based policy

Permite al IAM role `orion-agent-deploy-dev` (creado por
`modules/iam-orion-agent-dev`) pushear imagenes al repo.

Pull NO se incluye explicitamente aqui — el AgentCore Runtime en Sprint B.2
usara su propio IAM execution role (`orion-agent-exec-dev`), no el deploy role.

## Uso

```hcl
module "ecr_orion_agent" {
  source = "../modules/ecr-orion-agent"

  project_name   = "orion"
  environment    = "dev"
  deploy_role_arn = module.iam_orion_agent_dev.role_arn
  max_image_count = 30
}
```

## Outputs

- `repository_uri` — `<account>.dkr.ecr.us-east-1.amazonaws.com/orion-agent`.
  El workflow de deploy hace `docker tag ...:SHA <repository_uri>:SHA` y
  `docker push <repository_uri>:SHA`.
- `repository_arn` — ARN completo del recurso. Set as SSM parameter
  `/orion/agent/ecr-repo-arn` para cross-repo consumption
  (orion-cognitive-agent lo lee en su deploy workflow).
- `repository_name` — `orion-agent` (literal).

## Notas

- `default_tags` (Project, Environment, ManagedBy, Repository) se aplican
  via `live/dev/providers.tf` (definido en el caller, no en este modulo).
- `lifecycle_policy` esta versionada como JSON encodeada (no como
  `aws_ecr_lifecycle_policy_document` data source, porque el data source
  no soporta `tagStatus: any + countType: imageCountMoreThan` con
  parametrizacion cross-platform — el JSON inline es portable).
- Pendiente Sprint C: cuando el IAM execution role del Runtime este
  creado, agregar una segunda statement al RBP para permitirle pull.
