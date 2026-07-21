# Module: `orion-infrastructure::iam-apigateway-authorizer-invoke`

Crea el IAM role que **API Gateway asume** para invocar el Lambda authorizer
(REQUEST type) configurado en `orion-backend`.

## Por que este role existe

API Gateway HTTP API v2 con un Lambda Authorizer de tipo `REQUEST` necesita
**dos roles distintos** para entregar una peticion a una ruta protegida:

1. **Execution role del authorizer Lambda** (`orion-<env>-lambda-exec-*`):
   trust `lambda.amazonaws.com`. Es el role que la Lambda function usa para
   arrancar (logs, VPC ENI, X-Ray, secrets). No es relevante para la
   invocacion desde API Gateway.
2. **Invoke role del authorizer** (este modulo, `orion-<env>-authorizer-invoke-*`):
   trust `apigateway.amazonaws.com`. Es el role que API Gateway ASSUME para
   hacer `lambda:InvokeFunction` sobre el authorizer Lambda.

Sin este role dedicado (con `lambda:InvokeFunction` y el trust correcto), API
Gateway no puede invocar el authorizer y devuelve **500 en TODAS las rutas
protegidas**. SAM no lo crea por default; el rol se debe provisionar aparte y
referenciar su ARN via `AuthorizerCredentialsArn` en el `AWS::ApiGatewayV2::Authorizer`.

## Que hace

- **`aws_iam_role`** `<project>-<env>-authorizer-invoke-<random>` con
  trust policy: `apigateway.amazonaws.com` (sin condiciones para dev; prod
  deberia aniadir `aws:SourceAccount` y `aws:SourceArn`). El prefijo se
  acorta a `authorizer-invoke` (sin `apigateway-`) porque AWS IAM limita
  `name_prefix` a 38 chars (64 - 26 del sufijo aleatorio).
- **1 inline policy**:
  - `lambda:InvokeFunction` sobre `var.authorizer_function_arn` (single-ARN
    scope, no wildcard).

## Uso

```hcl
module "iam_apigateway_authorizer_invoke" {
  source = "../../modules/iam-apigateway-authorizer-invoke"

  project_name = "orion"
  environment  = "dev"

  authorizer_function_arn = "arn:aws:lambda:us-east-1:681526276858:function:orion-authorizer-dev"

  tags = local.common_tags
}
```

El output `role_arn` se cablea a `live/dev/outputs.tf` como
`apigateway_authorizer_invoke_role_arn`, y de ahi a:

- `orion-backend` workflow `CD - Deploy` (parametro `ApigatewayAuthorizerInvokeRoleArn`
  de `template.yaml`, resolvido en runtime via `--parameter-overrides`).
- `orion-infrastructure` `modules/iam-sam-deploy-dev` como entry en
  `iam_role_arns` (para que `sam deploy` pueda `iam:PassRole` este role a
  CloudFormation).

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `authorizer_function_arn` | requerido | ARN del Lambda authorizer (e.g. `orion-authorizer-dev`). |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `role_arn` | ARN del role. Usar como `AuthorizerCredentialsArn` en SAM. |
| `role_name`, `role_unique_id` | Identificadores. |

## Decisiones de diseno

- **Trust policy sin condiciones**: para dev. Prod deberia aniadir
  `aws:SourceAccount = <this-account>` y opcionalmente
  `aws:SourceArn = arn:aws:execute-api:...:<api-id>/*/*` para evitar
  confusion attacks (otro API Gateway en la misma cuenta invocando el
  authorizer con esta role).
- **Sin VPC ni SG**: API Gateway invoca por IAM, no por red. No aplica
  LambdaBasicExecutionRole ni AWSLambdaVPCAccessExecutionRole.
- **Single-ARN scope en `lambda:InvokeFunction`**: least privilege. NO
  se usa `*` para que un compromise de esta role no permita invocar
  cualquier Lambda de la cuenta.
- **`name_prefix` con sufijo aleatorio**: patron consistente con
  `iam-lambda-exec`. Permite multiples instancias del modulo sin colision
  de nombres (e.g. dev/staging/prod en la misma cuenta en el futuro).

## Checkov skips

- `CKV_AWS_60`, `CKV_AWS_61`: trust limited to service principal.
- `CKV_AWS_107/108/109/110`: actions especificas, no privilege escalation.
- `CKV_AWS_111`, `CKV_AWS_356`, `CKV_AWS_290`: action unica, scope a ARN
  explicito.

## Diferencias para prod (futuro)

- Aniadir condicion `aws:SourceAccount` y `aws:SourceArn` al trust policy
  (acotar cual API puede assumir el role).
- Considerar `max_session_duration = 900` (default 1h es alto para un
  invoke role de corta duracion; minimo 900s segun AWS docs).
