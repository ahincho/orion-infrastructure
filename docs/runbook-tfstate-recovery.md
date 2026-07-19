# Runbook - Recuperacion del state bucket

El bucket `orion-tfstate-dev` es el source of truth de la infraestructura.
**Si se pierde, se pierde toda la historia de los recursos creados por
Terraform** y se vuelve imposible hacer `terraform plan`/`apply` sin recrear
manualmente todo.

Este runbook cubre los escenarios mas comunes.

---

## Escenario 1: state se corrompe (apply deja state inconsistente)

**Sintoma:** `terraform plan` muestra deltas inesperados, o `terraform apply`
falla con "Error: state snapshot was created from a different state file".

**Recuperacion** (gracias a versioning del bucket):

```bash
# 1. Listar versiones del state
aws s3api list-object-versions \
  --bucket orion-tfstate-dev \
  --prefix dev/terraform.tfstate \
  --query '"'"'Versions[].{VersionId:VersionId,LastModified:LastModified}'"'"' \
  --output table

# 2. Identificar la version "buena".
#    Tip: comparar timestamps con el ultimo apply exitoso en GitHub Actions
#    (gh run list --workflow=terraform-apply.yml --status=success)

# 3. Restaurar a esa version
aws s3api get-object \
  --bucket orion-tfstate-dev \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.recovered

aws s3 cp /tmp/terraform.tfstate.recovered \
  s3://orion-tfstate-dev/dev/terraform.tfstate

# 4. Verificar
cd live/dev && terraform plan
```

---

## Escenario 2: state se borra accidentalmente (el bucket sigue existiendo)

**Sintoma:** `terraform init` muestra "Error: Failed to read state file... NoSuchKey".

**Recuperacion:**

```bash
# 1. Listar versiones borradas (soft-delete en S3 versioning)
aws s3api list-object-versions \
  --bucket orion-tfstate-dev \
  --prefix dev/terraform.tfstate

# 2. Si aparece como "DeleteMarker", removerlo
aws s3api delete-object \
  --bucket orion-tfstate-dev \
  --key dev/terraform.tfstate \
  --version-id <DELETE_MARKER_VERSION_ID>

# 3. Si el state se borro completamente, no hay nada que recuperar.
#    Solucion: hacer `terraform import` de cada recurso o recrear todo.
```

---

## Escenario 3: el bucket completo se borra (worst case)

**Sintoma:** el bucket `orion-tfstate-dev` no existe. `terraform init`
muestra "Error: Failed to get S3 bucket".

**Prevencion:** en este escenario NO HAY recovery posible desde S3. Las
defensas son:

1. **Snapshots cross-region** (recomendado): configurar CRR
   (Cross-Region Replication) del bucket a otro bucket en otra region.
2. **Backup offline:**

   ```bash
   aws s3 cp s3://orion-tfstate-dev/dev/terraform.tfstate \
     ./backups/tfstate-dev-$(date +%Y%m%d).tfstate
   ```

3. **Re-bootstrap + terraform import** (si no hay backup):

   ```bash
   ./scripts/bootstrap-backend.sh
   cd live/dev
   terraform init   # con backend vacio
   # terraform import <resource.address> <id>  por cada recurso
   ```

---

## Escenario 4: state existe pero apunta a recursos que no existen en AWS (drift severo)

**Sintoma:** `terraform plan` muestra que va a recrear muchos recursos.

**Diagnostico:**

```bash
cd live/dev
terraform plan -detailed-exitcode
# exit 0 = sin cambios
# exit 1 = error
# exit 2 = hay cambios (drift detectado)

terraform state list
```

**Opciones:**

- Si los recursos fueron borrados a mano y queres recuperarlos:
  `terraform apply` (los recrea).
- Si los recursos fueron movidos: `terraform state mv` o
  `terraform state rm` + `terraform import`.

---

## Checklist post-incidente

Despues de cualquier incidente con el state:

- [ ] Verificar que `terraform plan` no muestra deltas inesperados
- [ ] Confirmar que el run mas reciente de `terraform-apply.yml` paso
- [ ] Documentar el incidente en el issue tracker
- [ ] Si fue por error humano, evaluar agregar mas validaciones o gates
- [ ] Si fue por bug de Terraform/provider, evaluar pin de version

---

## Monitoreo del bucket (recomendado)

Configurar CloudWatch alarm o GitHub Action periodico (cron semanal) que
verifique:

- `s3:ListBucket` retorna resultados esperados
- `s3:GetObject` en `terraform.tfstate` retorna sin error
- El size del state es razonable (<1MB para nuestro caso)
- Versioning sigue habilitado
- KMS encryption sigue activo