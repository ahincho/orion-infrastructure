# modules/ecr-orion-agent

ECR repository privado para las imagenes del OrionAgent deployadas en
Bedrock AgentCore.

## Recursos que crea

| Recurso | Nombre | Proposito |
|---|---|---|
| `aws_ecr_repository` | `<project_name>-agent-<env>` | Repo privado AES256 + scan_on_push |
| `aws_ecr_lifecycle_policy` | (idem) | Retiene max N imagenes; expira el resto |
| `aws_ecr_repository_policy` | (idem) | Otorga pull a principals ARN-listados |

## Inputs

| Nombre | Tipo | Default | Descripcion |
|---|---|---|---|
| `project_name` | `string` | (requerido) | kebab-case, 3-30 chars. Validado. |
| `environment` | `string` | (requerido) | `dev`/`staging`/`prod`. Validado. |
| `image_tag_mutability` | `string` | `"IMMUTABLE"` | `MUTABLE` o `IMMUTABLE`. |
| `scan_on_push` | `bool` | `true` | ECR Basic scan automatico al push. |
| `max_image_count` | `number` | `30` | Cap de retention del lifecycle. 1-1000. |
| `principal_arns_with_pull` | `list(string)` | `[]` | IAM principals con permiso de pull. Default vacio = repo privado sin acceso externo. |
| `tags` | `map(string)` | `{}` | Tags adicionales. |

`force_delete = true` solo si `environment == "dev"` para permitir
`terraform destroy` rapido sin error de "repository not empty".

## Outputs

| Nombre | Descripcion |
|---|---|
| `repository_id` | ID interno del repo. |
| `repository_arn` | ARN completo (e.g. `arn:aws:ecr:us-east-1:681526276858:repository/orion-agent-dev`). Wire a `var.ecr_repository_arn` del modulo `iam-orion-agent-dev`. |
| `repository_name` | Nombre corto. |
| `repository_url` | Registry URL completa (e.g. `681526276858.dkr.ecr.us-east-1.amazonaws.com/orion-agent-dev`). Usar en comandos `docker push`. |

## Skip de Checkov

- `CKV_AWS_51` / `CKV_AWS_136` — AES256 explicito para free-tier (KMS CMK cuesta ~$1/mes).
- `CKV_AWS_163` — Basic scanning es zero-cost vs Inspector (free-tier).
- `CKV_AWS_283` — `principal_arns_with_pull` ya restringe el acceso (default `[]`).

Razon por skip inline en `main.tf`.
