# ORION - Infraestructura como Codigo

Infraestructura AWS del proyecto **ORION** (Sistema Cognitivo), gestionada con
**Terraform puro** y pipelines reutilizables desde
`spark-match/spark-match-01-devops`.

> **Owner:** `@ahincho` (solo, proyecto rapido)
> **Repo:** [ahincho/orion-infrastructure](https://github.com/ahincho/orion-infrastructure)

---

## Stack

- **Cloud:** AWS (default `us-east-1`, cuenta TBD por el owner)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 + native lockfile (`use_lockfile = true`)
- **Pipelines:** [Reusable workflows](https://github.com/spark-match/spark-match-01-devops/tree/main/.github/workflows)
  desde `spark-match/spark-match-01-devops` pinneados `@dev`.
- **Linting:** tflint, terraform fmt, pre-commit-terraform, yamllint, actionlint

---

## Estado actual (Phase 0)

Este repo esta en **Phase 0** (fundacion). Recursos que se crean:

- **1 bucket S3** (`orion-tfstate-dev`) para state remoto con versioning
  + AES256 + bloqueo de acceso publico + native lockfile.
- **1 IAM OIDC provider** para GitHub Actions (thumbprint
  `6938fd4d98bab03faadb97b34396831e3780aea1`).
- **2 IAM roles OIDC:**
  - `orion-terraform-plan` (read-only, OIDC)
  - `orion-terraform-apply` (write, OIDC)

No hay VPC, NAT, endpoints, ni recursos runtime de ORION todavia - esos
vienen en Phase 1+.

---

## Single-env setup (dev)

| Aspecto | dev |
|---|---|
| **Branch protegido** | `main` |
| **GitHub Environment** | `dev` (sin reviewers, `auto-approve=true`) |
| **State bucket** | `orion-tfstate-dev` |
| **State key** | `dev/terraform.tfstate` |
| **AWS Region** | `us-east-1` |
| **Locking** | S3 native lockfile |
| **Encryption** | AES256 server-side |
| **Reusables pinning** | `@dev` (unico env) |
| **Workflow triggers** | push a `main` (apply), PR a `main` (plan), `workflow_dispatch` |

### Flujo

```
PR abierto contra main
  â”€â–º terraform-plan.yml corre Plan (dev)
      â”€â–º Sticky comment en PR con tabla de cambios

PR mergeado a main (squash)
  â”€â–º terraform-apply.yml â†’ Apply (dev)
      â”€â–º GH Environment "dev" (auto-approve=true)
```

---

## Estructura

```
orion-infrastructure/
â”œâ”€â”€ AGENTS.md                              # Convenciones operacionales
â”œâ”€â”€ README.md                              # Este archivo
â”œâ”€â”€ LICENSE                                # MIT
â”œâ”€â”€ .gitignore
â”œâ”€â”€ .pre-commit-config.yaml                # terraform + shell + yaml hooks
â”œâ”€â”€ .tflint.hcl                            # Terraform lint rules
â”œâ”€â”€ .yamllint.yml                          # YAML lint rules
â”œâ”€â”€ .github/
â”‚   â”œâ”€â”€ CODEOWNERS                         # ahincho (solo)
â”‚   â”œâ”€â”€ dependabot.yml                     # Terraform providers + GH Actions
â”‚   â”œâ”€â”€ PULL_REQUEST_TEMPLATE.md
â”‚   â””â”€â”€ workflows/
â”‚       â”œâ”€â”€ ci.yml                         # actionlint + yamllint + tflint (PR)
â”‚       â”œâ”€â”€ terraform-plan.yml             # caller â†’ spark-match-01-devops/terraform-plan.yml
â”‚       â””â”€â”€ terraform-apply.yml            # caller â†’ spark-match-01-devops/terraform-apply.yml
â”œâ”€â”€ live/
â”‚   â””â”€â”€ dev/
â”‚       â”œâ”€â”€ main.tf                        # instantiate modules
â”‚       â”œâ”€â”€ outputs.tf
â”‚       â”œâ”€â”€ providers.tf
â”‚       â”œâ”€â”€ versions.tf
â”‚       â”œâ”€â”€ variables.tf
â”‚       â”œâ”€â”€ terraform.tfvars
â”‚       â””â”€â”€ terraform.tfvars.example
â”œâ”€â”€ modules/
â”‚   â”œâ”€â”€ storage-tfstate/                   # S3 bucket para state
â”‚   â”‚   â”œâ”€â”€ main.tf
â”‚   â”‚   â”œâ”€â”€ variables.tf
â”‚   â”‚   â”œâ”€â”€ outputs.tf
â”‚   â”‚   â”œâ”€â”€ versions.tf
â”‚   â”‚   â””â”€â”€ README.md
â”‚   â””â”€â”€ oidc-github/                       # OIDC provider + 2 IAM roles
â”‚       â”œâ”€â”€ main.tf
â”‚       â”œâ”€â”€ variables.tf
â”‚       â”œâ”€â”€ outputs.tf
â”‚       â”œâ”€â”€ versions.tf
â”‚       â””â”€â”€ README.md
â”œâ”€â”€ scripts/
â”‚   â”œâ”€â”€ bootstrap-backend.sh               # Crea bucket S3 (idempotente)
â”‚   â”œâ”€â”€ setup-oidc.sh                      # Crea OIDC provider + 2 roles
â”‚   â”œâ”€â”€ plan.sh                            # terraform plan wrapper
â”‚   â””â”€â”€ apply.sh                           # terraform apply wrapper
â””â”€â”€ docs/
    â”œâ”€â”€ SETUP.md                           # Pasos OIDC + GH Secrets + Env
    â””â”€â”€ runbook-tfstate-recovery.md        # Escenarios de recuperacion de state
```

---

## Pre-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configurado con un perfil o variables
- [GitHub CLI](https://cli.github.com/) con permisos de admin en
  `ahincho/orion-infrastructure`
- (Opcional) [pre-commit](https://pre-commit.com/) + [tflint](https://github.com/terraform-linters/tflint)

---

## Bootstrap (primera vez)

Antes del primer `terraform init`, hay que crear el bucket S3 para el state
**fuera de Terraform** (chicken-and-egg). El script es idempotente.

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-backend.sh
```

Esto crea el bucket `orion-tfstate-dev` con:
- Versionado habilitado (obligatorio para state + lockfile)
- Encriptacion server-side AES256
- Acceso publico bloqueado (4 flags)
- Lock: `use_lockfile = true` (Terraform `>= 1.6`). **NO se crea tabla
  DynamoDB.**

Verificar manualmente:

```bash
aws s3api get-bucket-versioning --bucket orion-tfstate-dev
aws s3api get-bucket-encryption --bucket orion-tfstate-dev
aws s3api get-public-access-block --bucket orion-tfstate-dev
```

---

## Uso diario

```bash
cd live/dev

terraform init -input=false \
  -backend-config="bucket=orion-tfstate-dev" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

# Auto-load terraform.tfvars (commiteado con valores del env)
./../../scripts/plan.sh dev
./../../scripts/apply.sh dev
```

---

## Workflow de cambios

1. **Crear rama desde `main`** con prefijo:
   - `feat/<descripcion-corta>` para nuevas features
   - `fix/<descripcion-corta>` para bugfixes
   - `chore/<descripcion-corta>` para housekeeping
   - `docs/<descripcion-corta>` para documentacion

2. **Validar localmente**:

   ```bash
   pre-commit run --all-files
   cd live/dev && terraform init -backend=false && terraform validate
   ```

3. **Push y abrir PR contra main**:
   - El PR dispara `CI - Lint & Security` (actionlint + yamllint + tflint).
   - El PR dispara `CD - Terraform Plan` que planea dev (sticky comment).

4. **Merge via squash** a `main`. Esto triggerea `CD - Terraform Apply`
   automaticamente contra el GH Environment `dev` (auto-approve).

---

## Anadir un nuevo modulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/dev/main.tf`

---

## Autenticacion AWS: OIDC

GitHub Actions asume roles IAM en AWS via **OIDC** (sin access keys de larga
duracion). Trust policy restringida al repo
`ahincho/orion-infrastructure` + main branch + GH Environment `dev`.

### Roles Terraform plan/apply (creados por `modules/oidc-github`)

| Role | ARN (formato) | Permisos | Secret en GH |
|---|---|---|---|
| `orion-terraform-plan` | `arn:aws:iam::{account}:role/orion-terraform-plan` | read-only sobre AWS | `AWS_PLAN_ROLE_ARN` |
| `orion-terraform-apply` | `arn:aws:iam::{account}:role/orion-terraform-apply` | `Action:*` restringido a region | `AWS_APPLY_ROLE_ARN` |

> El caller `terraform-plan.yml` corre plan con `-lock=false` porque el S3
> native lockfile requiere `PutObject` (write). El plan es read-only por
> naturaleza, no necesita lock.

---

## Licencia

MIT - ver `LICENSE`.