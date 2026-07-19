# Module: storage-tfstate

Crea el bucket S3 para state remoto de Terraform con:

- Versionado habilitado (obligatorio para state + lockfile)
- Encriptacion server-side AES256 (FIPS 140-2 compliant)
- Acceso publico bloqueado (4 flags)

## Uso

Una invocacion por ambiente (este repo solo soporta `environment=dev`,
pero el modulo es reutilizable).

```hcl
module "storage_tfstate" {
  source = "../../modules/storage-tfstate"

  project_name = "orion"
  environment  = "dev"
  aws_region   = "us-east-1"
}
```

Resultado: bucket `orion-tfstate-dev` con la configuracion arriba descrita.

## Primera vez

El bucket NO se puede crear dentro de Terraform (chicken-and-egg). La primera
vez se crea via `scripts/bootstrap-backend.sh` antes del primer
`terraform init`. Las invocaciones siguientes del modulo son idempotentes.

## Lifecycle (opcional)

Variables `lifecycle_transition_to_ia_days` y
`lifecycle_transition_to_glacier_days` permiten transicionar objetos a clases
mas baratas. Por defecto deshabilitados (0 = disabled).