# Module: `orion-infrastructure::secrets-bootstrap`

Crea el secret JWT HS256 signing key en AWS Secrets Manager para
orion-backend (`contexts/identity` + `contexts/authorizer`).

## Que hace

- Genera un random 64+ char JWT signing key via `random_password`.
- Crea un secret `aws_secretsmanager_secret` con el nombre
  `${project_name}-${environment}-${jwt_secret_name_suffix}` (default
  `orion-dev-jwt-signing-secret`).
- Crea la version inicial con un payload JSON estructurado:
  ```json
  {
    "version": 1,
    "alg": "HS256",
    "kty": "oct",
    "use": "sig",
    "key": "<random-password>",
    "rotatedAt": "<iso8601>"
  }
  ```
- Tags consistentes con los otros modulos.

## Uso

```hcl
module "secrets" {
  source = "../../modules/secrets-bootstrap"

  project_name             = "orion"
  environment              = "dev"
  jwt_secret_length        = 64
  recovery_window_in_days  = 0   # dev: delete OK; staging/prod: 7+

  tags = local.common_tags
}

# Exponer el ARN del secret via SSM para que orion-backend lo resuelva
# en tiempo de deploy:
resource "aws_ssm_parameter" "jwt_arn" {
  name  = "/orion/secret/jwt-arn"
  type  = "String"
  value = module.secrets.jwt_signing_secret_arn
}
```

## Variables

| Nombre | Default | Descripcion |
|---|---|---|
| `project_name` | requerido | kebab-case (3-30). |
| `environment` | requerido | `dev` \| `staging` \| `prod`. |
| `jwt_secret_name_suffix` | `jwt-signing-secret` | Sufijo del nombre del secret. |
| `jwt_secret_length` | `64` | Min 32 (HS256 baseline), max 128. |
| `recovery_window_in_days` | `0` | `0`=delete inmediato, `7+`=con rollback. |
| `tags` | `{}` | Tags extra. |

## Outputs

| Nombre | Descripcion |
|---|---|
| `jwt_signing_secret_arn` | ARN completo. |
| `jwt_signing_secret_name` | Solo el nombre (sin ARN). |
| `jwt_signing_secret_id` | ID con sufijo random AWS. |
| `jwt_signing_initial_version_id` | ID de la version inicial. |

## Decisiones de diseno

- **Generacion con `random_password`**: el valor generado vive en el
  state de Terraform (no en el `secret_string` en claro). Es
  regenerable si el state se pierde (rotacion manual via
  `terraform taint resource.random_password.jwt_signing`).
- **Sin `kms_key_id`**: la encryption at-rest la provee el AWS-managed
  CMK de Secrets Manager (sufciente para dev). Para prod se suministrara
  un CMK explicito via un futuro `modules/kms/`.
- **Sin rotacion automatica**: rotar el JWT signing key requiere
  invalidar todos los tokens emitidos y re-firmarlos con el nuevo
  key. Es una operacion mayor que se hara via un Lambda custom
  (futuro `modules/secrets-rotation/`).
- **`recovery_window_in_days = 0` en dev**: permite `terraform destroy`
  borrar el secret sin esperar 7-30 dias. Para staging/prod subir a 7+.

## Checkov skips

- `CKV_AWS_149` (backing key rotation): rotacion no implementada todavia.
- `CKV_AWS_173` (encryption with KMS CMK): AWS-managed CMK en dev.
- `CKV2_AWS_57` (resource-based policy): no requerida; acceso via IAM.

## Integracion esperada con otros modulos ORION

```hcl
# Modulo: modules/ssm-bootstrap/ (PR #28)
resource "aws_ssm_parameter" "jwt_secret_arn" {
  name  = "/orion/secret/jwt-arn"
  type  = "String"
  value = module.secrets.jwt_signing_secret_arn
}

# Modulo: modules/iam-lambda-exec/ (PR #31)
data "aws_iam_policy_document" "lambda_secrets_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.secrets.jwt_signing_secret_arn]
  }
}
```

orion-backend (template.yaml) lo consume como:
```yaml
JWT_SECRET_ARN: '{{resolve:ssm:/orion/secret/jwt-arn}}'
```
