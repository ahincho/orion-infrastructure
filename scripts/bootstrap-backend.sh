#!/bin/bash
# ============================================================================
# bootstrap-backend.sh
# Crea el bucket S3 para state remoto de Terraform. Idempotente.
#
# Se ejecuta UNA VEZ antes del primer `terraform init` en el ambiente.
#
# El locking se hace con S3 native lockfile (Terraform >= 1.6),
# por lo que NO se crea tabla DynamoDB.
#
# Validado con Terraform 1.15.7 + AWS CLI bajo perfil `orion-admin`.
# (usa `aws configure get aws_access_key_id --profile orion-admin` para
#  ver el Key ID actual bajo esa perfil; nunca hardcodear el AKIA aqui.)
#
# Usage:
#   AWS_PROFILE=orion-admin ./scripts/bootstrap-backend.sh            # default dev
#   AWS_PROFILE=orion-admin ENVIRONMENT=prod ./scripts/bootstrap-backend.sh
#
# Si vienes de versiones anteriores que creaban DynamoDB, esa tabla
# quedara huerfana y deberas limpiarla manualmente:
#   aws dynamodb delete-table --table-name orion-tflock --region us-east-1
# ============================================================================
set -euo pipefail

# --- Configuracion (ajustar via env vars) ---
PROJECT_NAME="${PROJECT_NAME:-orion}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STATE_BUCKET="${PROJECT_NAME}-tfstate-${ENVIRONMENT}"

echo "=========================================="
echo "  Bootstrap Terraform Backend (S3 only)"
echo "  Region:  ${AWS_REGION}"
echo "  Bucket:  ${STATE_BUCKET}"
echo "  Locking: S3 native lockfile (use_lockfile=true)"
echo "=========================================="

if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo "[ERROR] No hay credenciales AWS configuradas."
  echo "        Configura AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY o usa aws configure."
  exit 1
fi

if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "[OK] Bucket ${STATE_BUCKET} ya existe."
else
  echo "[INFO] Creando bucket S3 ${STATE_BUCKET}..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi

  aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration '"'"'{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'"'"'

  aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "[OK] Bucket creado con versionado + encriptacion + acceso publico bloqueado."
fi

if aws dynamodb describe-table --table-name "${PROJECT_NAME}-tflock" \
    --region "${AWS_REGION}" > /dev/null 2>&1; then
  echo ""
  echo "[WARN] Tabla DynamoDB ${PROJECT_NAME}-tflock detectada."
  echo "       Con S3 native lockfile ya no se usa. Puedes eliminarla con:"
  echo "         aws dynamodb delete-table --table-name ${PROJECT_NAME}-tflock --region ${AWS_REGION}"
fi

echo ""
echo "=========================================="
echo "  Bootstrap completo!"
echo "  Siguiente paso (desde el repo):"
echo "    cd live/${ENVIRONMENT}"
echo "    terraform init -input=false \\"
echo "                    -backend-config=\"bucket=${STATE_BUCKET}\" \\"
echo "                    -backend-config=\"key=${ENVIRONMENT}/terraform.tfstate\" \\"
echo "                    -backend-config=\"region=${AWS_REGION}\" \\"
echo "                    -backend-config=\"use_lockfile=true\""
echo "=========================================="