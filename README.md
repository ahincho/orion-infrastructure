# ORION — Infraestructura como Código

Infraestructura AWS del proyecto **ORION** (Pequeño Sistema Cognitivo),
gestionada con **Terraform puro** y pipelines reutilizables desde
`spark-match/spark-match-01-devops`.

> **Owner:** `@ahincho` (solo)
> **Repo:** [ahincho/orion-infrastructure-devops](https://github.com/ahincho/orion-infrastructure-devops)

---

## Stack

- **Cloud:** AWS (default `us-east-1`, cuenta TBD por el owner)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 + native lockfile (`use_lockfile = true`)
- **Pipelines:** [Reusable workflows](https://github.com/spark-match/spark-match-01-devops/tree/main/.github/workflows)
  desde `spark-match/spark-match-01-devops` (pin `@dev` para dev, `@main` para prod)
- **Linting:** tflint, terraform fmt, pre-commit-terraform, yamllint, actionlint

---

## Estado actual (Phase 0)

Este repo está en **Phase 0** (fundación). Recursos que se crean:

- **2 buckets S3** (`orion-tfstate-dev`, `orion-tfstate-prod`) para state remoto
  con versioning + AES256 + bloqueo de acceso público + native lockfile
- **1 IAM OIDC provider** para GitHub Actions (thumbprint
  `6938fd4d98bab03faadb97b34396831e3780aea1`)
- **4 IAM roles OIDC** (uno por `(env, capability)`):
  - `orion-terraform-plan-dev` (read-only, OIDC)
  - `orion-terraform-apply-dev` (write, OIDC)
  - `orion-terraform-plan-prod` (read-only, OIDC)
  - `orion-terraform-apply-prod` (write, OIDC)

No hay VPC, NAT, endpoints, ni recursos runtime de ORION todavía — esos
vienen en Phase 1+.

---

## Multi-env setup (dev + prod)

| Aspecto | dev | prod |
|---|---|---|
| **Branch** | `dev` | `main` |
| **GitHub Environment** | `dev` (sin reviewers, `auto-approve=true`) | `production` (con reviewer `@ahincho`) |
| **State bucket** | `orion-tfstate-dev` | `orion-tfstate-prod` |
| **State key** | `dev/terraform.tfstate` | `prod/terraform.tfstate` |
| **AWS Region** | `us-east-1` | `us-east-1` |
| **Locking** | S3 native lockfile | S3 native lockfile |
| **Encryption** | AES256 server-side | AES256 server-side |
| **Workflows reusables** | pinned `@dev` | pinned `@main` |
| **Triggers** | push a `dev`, workflow_dispatch con `environment=dev` | push a `main`, workflow_dispatch con `environment=prod` |

### Diagrama de flujo

```
PR abierto contra dev
  └─> terraform-plan.yml corre Plan (dev)
      ├─> Plan dev: working-dir=live/dev, bucket=orion-tfstate-dev
      └─> Sticky comment en PR con tabla de cambios

Merge a dev branch
  └─> terraform-apply.yml -> apply-dev
      └─> GH Environment "dev" (auto-approve=true)

PR de dev a main
  └─> terraform-plan.yml corre Plan (prod) en el PR a main
  └─> Aprobar
  └─> Merge
      └─> terraform-apply.yml -> apply-prod
          └─> GH Environment "production" (requiere aprobación)
```

---

## Estructura

```
orion-infrastructure-devops/
├── AGENTS.md                              # Convenciones operacionales
├── README.md                              # Este archivo
├── LICENSE                                # MIT
├── .gitignore
├── .pre-commit-config.yaml                # terraform + shell + yaml hooks
├── .tflint.hcl                            # Terraform lint rules
├── .yamllint.yml                          # YAML lint rules
├── .github/
│   ├── CODEOWNERS                         # ahincho (solo)
│   ├── dependabot.yml                     # Terraform providers + GH Actions
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── ci.yml                         # actionlint + yamllint (PR)
│       ├── terraform-plan.yml             # caller → 01-devops/terraform-plan.yml
│       └── terraform-apply.yml            # caller → 01-devops/terraform-apply.yml
├── live/
│   ├── dev/
│   │   ├── main.tf                        # instantiate modules
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── versions.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── terraform.tfvars.example
│   └── prod/                              # mismo esqueleto, valores prod
├── modules/
│   ├── storage-tfstate/                   # S3 bucket para state
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md
│   └── oidc-github/                       # OIDC provider + 4 IAM roles
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── README.md
├── scripts/
│   ├── bootstrap-backend.sh               # Crea buckets S3 (idempotente)
│   ├── setup-oidc.sh                      # Crea OIDC provider + 4 roles
│   ├── plan.sh                            # terraform plan wrapper
│   └── apply.sh                           # terraform apply wrapper
└── docs/
    ├── SETUP.md                           # Pasos OIDC + GH Secrets + Envs
    └── runbook-tfstate-recovery.md        # Escenarios de recuperacion de state
```

---

## Pre-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configurado con un perfil o variables
- [GitHub CLI](https://cli.github.com/) con permisos de admin en
  `ahincho/orion-infrastructure-devops`
- (Opcional) [pre-commit](https://pre-commit.com/) + [tflint](https://github.com/terraform-linters/tflint)

---

## Bootstrap (primera vez por ambiente)

Antes del primer `terraform init`, hay que crear el bucket S3 para el state
**fuera de Terraform** (chicken-and-egg: Terraform no puede crear su propio
state bucket). El script es idempotente.

```bash
chmod +x scripts/*.sh

# Bootstrap dev
ENVIRONMENT=dev AWS_REGION=us-east-1 ./scripts/bootstrap-backend.sh

# Bootstrap prod
ENVIRONMENT=prod AWS_REGION=us-east-1 ./scripts/bootstrap-backend.sh
```

Esto crea el bucket `orion-tfstate-{env}` con:
- Versionado habilitado (obligatorio para state + lockfile)
- Encriptación server-side AES256
- Acceso público bloqueado (4 flags)
- Lock: `use_lockfile = true` (Terraform `>= 1.6`). **NO se crea tabla
  DynamoDB.**

Verificar manualmente:
```bash
aws s3api get-bucket-versioning --bucket orion-tfstate-dev
aws s3api get-bucket-encryption --bucket orion-tfstate-dev
aws s3api get-public-access-block --bucket orion-tfstate-dev
```

---

## Uso diario (dev)

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

Para prod: mismo flujo en `live/prod`.

---

## Workflow de cambios

1. **Crear rama desde `dev`** con prefijo:
   - `feat/<descripcion-corta>` para nuevas features
   - `fix/<descripcion-corta>` para bugfixes
   - `chore/<descripcion-corta>` para housekeeping
   - `docs/<descripcion-corta>` para documentacion

2. **Validar localmente**:
   ```bash
   pre-commit run --all-files
   cd live/dev && terraform init -backend=false && terraform validate
   cd live/prod && terraform init -backend=false && terraform validate
   ```

3. **Push a dev y abrir PR contra dev**:
   - El PR dispara `CI - Lint & Security` (actionlint + yamllint).
   - El PR dispara `CD - Terraform Plan` que planea dev (sticky comment).

4. **Merge via squash** a `dev`.

5. **Sync a main (promover cambios)**:
   - Abrir PR de `dev` a `main` con título `chore: sync dev into main`.
   - Como admin, mergear con bypass.
   - Esto triggerea `CD - Terraform Apply - production` que requiere
     aprobación manual del GH Environment `production`.

---

## Añadir un nuevo módulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/dev/main.tf` y
   `live/prod/main.tf`
4. (Opcional) agregar variables en `live/{dev,prod}/variables.tf` y defaults
   en `terraform.tfvars`

---

## 🔐 Autenticación AWS: OIDC

GitHub Actions asume roles IAM en AWS vía **OIDC** (sin access keys de larga
duración). Trust policy restringida al repo
`ahincho/orion-infrastructure-devops`.

### Roles Terraform plan/apply (creados por `modules/oidc-github`)

| Role | ARN (formato) | Trust policy | Secret en GH |
|---|---|---|---|
| `orion-terraform-plan-dev` | `arn:aws:iam::{account}:role/orion-terraform-plan-dev` | `repo:ahincho/orion-infrastructure-devops:ref:refs/heads/dev` + `pull_request` + `environment:dev` | `AWS_PLAN_ROLE_ARN_DEV` |
| `orion-terraform-apply-dev` | `arn:aws:iam::{account}:role/orion-terraform-apply-dev` | `repo:...:ref:refs/heads/dev` + `pull_request` + `environment:dev` | `AWS_APPLY_ROLE_ARN_DEV` |
| `orion-terraform-plan-prod` | `arn:aws:iam::{account}:role/orion-terraform-plan-prod` | `repo:...:ref:refs/heads/main` + `pull_request` + `environment:production` | `AWS_PLAN_ROLE_ARN_PROD` |
| `orion-terraform-apply-prod` | `arn:aws:iam::{account}:role/orion-terraform-apply-prod` | `repo:...:ref:refs/heads/main` + `pull_request` + `environment:production` | `AWS_APPLY_ROLE_ARN_PROD` |

> El caller `terraform-plan.yml` corre plan con `-lock=false` porque el S3
> native lockfile requiere `PutObject` (write). El plan es read-only por
> naturaleza, no necesita lock.

---

## Licencia

MIT — ver `LICENSE`.
