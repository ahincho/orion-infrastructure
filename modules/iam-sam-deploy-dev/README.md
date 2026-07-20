# Module: `iam-sam-deploy-dev`

Crea el IAM role + inline policy `SamDeployPolicy` que asume el workflow
`CD - Deploy` de [`ahincho/orion-backend`][backend] via GitHub OIDC para
correr `sam build` y `sam deploy` contra AWS.

Este modulo **reemplaza** al rol legacy `spark-match-sam-deploy-dev` que se
uso durante el bootstrap inicial (con prefijo heredado del proyecto anterior).
El nuevo rol es `orion-sam-deploy-dev`, Terraform-managed, con trust policy
exclusiva al repo orion-backend y ARN patterns `orion-*` (no `spark-match-*`).

## Outputs

| Output | Descripcion |
|---|---|
| `role_arn` | ARN del IAM role. Wire a GitHub Environment secret `AWS_DEPLOY_ROLE_ARN` (orion-backend / env: dev). |
| `role_name` | Nombre del role (sin ARN). |
| `role_id` | ID estable (role-unique). |

## Trust policy

Asumible solo desde:
- `repo:ahincho/orion-backend:ref:refs/heads/main` (push a main)
- `repo:ahincho/orion-backend:environment:dev` (jobs con `environment: dev`)

No aceptable desde forks, otras branches, ni el repo spark-match.

## Permisos (`SamDeployPolicy`)

18 statements inline, replicando los permisos parchados del rol legacy
`spark-match-sam-deploy-dev` (consolidado tras PRs #44, #86, #87, #88, #89):

| Statement | Scope |
|---|---|
| CloudFormationReadAll | read-only API global |
| CloudFormationManageBackendStack | `orion-backend-dev*` (+ nested via /<id>) |
| CloudFormationServerlessTransform | macro `Serverless-2016-10-31` (ARN fijo) |
| LambdaReadAll | read-only API global |
| LambdaManageFunctions | `orion-*-dev` functions + `:*` versions/aliases |
| LambdaManageLayers | `orion-{node,python}-{shared,runtime}-dev*` |
| ApiGatewayV2Manage | HTTP API v2 + `apigateway:GET` fallback |
| EventBridgeManageBusAndRules | rules + bus + archives bajo `orion-*` |
| IAMManageExecutionRoles | `orion-backend-dev*`, `orion-*-exec-dev`, `orion-lambda-runtime-dev*` |
| IAMPassRoleToLambdaAndEvents | scoped a `iam:PassedToService in [lambda, apigateway, events]` |
| S3SamArtifacts | `orion-sam-artifacts-dev*` + `orion-backend-deploy-dev*` |
| S3ReadTfStateForOutputs | `orion-tfstate-dev*` (read-only) |
| SSMReadParameters | `/orion/*` parameter store |
| KMSDecrypt | `key/*` con tag conditions `Project=orion Environment=dev` |
| CloudWatchLogsManage | `/aws/orion/*` + `/aws/lambda/orion-backend-dev*` |
| XRayTracing | API global |
| STSGetCallerIdentity | API global (requerido por aws-actions/configure-aws-credentials) |
| SqsDLQ | `orion-backend-dev*` (Lambda on_failure destinations) |

## Naming

`${var.project_name}-sam-deploy-${var.environment}` -> `orion-sam-deploy-dev`.

[backend]: https://github.com/ahincho/orion-backend
