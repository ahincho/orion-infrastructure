# Module: storage-tfstate

Crea el bucket S3 para almacenar el state de Terraform con versionado, AES256 y bloqueo de acceso publico.

## Uso

```hcl
module "storage_tfstate" {
  source = "../../modules/storage-tfstate"

  project_name = "orion"
  environment  = "dev"
  aws_region   = "us-east-1"
}
```

## Bootstrap manual

Antes del primer apply, crear el bucket fuera de Terraform:

```bash
ENVIRONMENT=dev ./scripts/bootstrap-backend.sh
```

El script es idempotente. Si el bucket ya existe (porque fue creado por un apply previo), no hace nada.

## Outputs

| Output | Descripcion |
|---|---|
| `bucket_id` | Nombre del bucket (ej. `orion-tfstate-dev`). |
| `bucket_arn` | ARN del bucket. |
| `bucket_region` | Region AWS donde vive. |
| `bucket_domain_name` | Domain name para endpoints S3. |

## Decisiones

- **AES256 server-side** (FIPS 140-2 compliant). No se migra a SSE-KMS por chicken-and-egg entre CMK y bucket.
- **Versioning enabled** (obligatorio para `terraform plan` post-recovery).
- **Locking**: `use_lockfile = true` en `versions.tf` (Terraform >= 1.6). NO se crea tabla DynamoDB.
- **Public access block** con 4 flags.
