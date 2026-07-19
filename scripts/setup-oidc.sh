#!/bin/bash
# ============================================================================
# setup-oidc.sh
# Crea el IAM OIDC provider de GitHub Actions + 2 IAM roles (plan + apply).
#
# USO:
#   - SOLO si NO usas Terraform para crear el OIDC (recomendamos Terraform).
#   - Caso normal: terraform apply (modulo oidc-github) hace todo esto.
#   - Este script es para bootstrap inicial ANTES del primer apply, en una
#     cuenta AWS nueva donde Terraform no tiene los permisos para crear
#     el OIDC provider.
#
# Pre-requisitos:
#   - AWS CLI configurado con un usuario/role con permisos iam:Create*.
#   - Tener un bucket S3 para state (corre bootstrap-backend.sh antes).
#
# Validado con Terraform 1.15.7 + AWS CLI bajo perfil `orion-admin`.
#
# Outputs (pegar en docs/SETUP.md):
#   - orion-terraform-plan-arn
#   - orion-terraform-apply-arn
# ============================================================================
set -euo pipefail

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-ahincho/orion-infrastructure}"
OIDC_THUMBPRINT="${OIDC_THUMBPRINT:-6938fd4d98bab03faadb97b34396831e3780aea1}"

echo "=========================================="
echo "  Setup OIDC for ORION infrastructure"
echo "  Repository: ${GITHUB_REPOSITORY}"
echo "=========================================="

if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo "[ERROR] No AWS credentials." >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

###############################################################################
# 1. IAM OIDC Provider (idempotente)
###############################################################################
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "${PROVIDER_ARN}" \
    > /dev/null 2>&1; then
  echo "[OK] OIDC provider already exists: ${PROVIDER_ARN}"
else
  echo "[INFO] Creating IAM OIDC provider for GitHub Actions..."
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list "${OIDC_THUMBPRINT}" > /dev/null
  echo "[OK] OIDC provider created."
fi

###############################################################################
# Helper: create or update IAM role with OIDC trust
###############################################################################
create_role() {
  local role_name="$1"
  local sub_pattern_json="$2"

  echo "[INFO] Creating role ${role_name}..."
  aws iam create-role \
    --role-name "${role_name}" \
    --assume-role-policy-document "${sub_pattern_json}" \
    --max-session-duration 3600 \
    --tags "Key=Project,Value=orion" \
           "Key=ManagedBy,Value=bootstrap-script" \
           "Key=Repository,Value=${GITHUB_REPOSITORY}" \
    > /dev/null 2>&1 || echo "  (role may already exist)"
}

attach_policy() {
  local role_name="$1"
  local policy_name="$2"
  local policy_json="$3"

  aws iam put-role-policy \
    --role-name "${role_name}" \
    --policy-name "${policy_name}" \
    --policy-document "${policy_json}" \
    > /dev/null
  echo "[OK] Policy ${policy_name} attached to ${role_name}"
}

###############################################################################
# 2. Roles plan (read-only) + apply (write)
###############################################################################
COMMON_TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${PROVIDER_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {"token.actions.githubusercontent.com:sub": "PLACEHOLDER"}
    }
  }]
}
EOF
)

PLAN_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:Describe*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:List*",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "sts:GetCallerIdentity"
    ],
    "Resource": "*"
  }]
}
EOF
)

APPLY_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "*",
    "Resource": "*",
    "Condition": {
      "StringEquals": {"aws:RequestedRegion": "us-east-1"}
    }
  }]
}
EOF
)

# sub patterns: cualquier push/PR contra main + jobs con environment:dev
SUB_PATTERNS='["repo:'"${GITHUB_REPOSITORY}"':ref:refs/heads/main","repo:'"${GITHUB_REPOSITORY}"':pull_request","repo:'"${GITHUB_REPOSITORY}"':environment:dev"]'

PLAN_TRUST=$(echo "${COMMON_TRUST}" | sed "s/\"PLACEHOLDER\"/$(printf '%s' "${SUB_PATTERNS}" | sed 's/"/\\"/g')/")

create_role "orion-terraform-plan" "${PLAN_TRUST}"
attach_policy "orion-terraform-plan" "plan-policy" "${PLAN_POLICY}"

create_role "orion-terraform-apply" "${PLAN_TRUST}"
attach_policy "orion-terraform-apply" "apply-policy" "${APPLY_POLICY}"

echo ""
echo "[SUCCESS] Roles created. ARNs:"
echo "  plan:  arn:aws:iam::${ACCOUNT_ID}:role/orion-terraform-plan"
echo "  apply: arn:aws:iam::${ACCOUNT_ID}:role/orion-terraform-apply"
echo ""
echo "Siguiente paso: docs/SETUP.md (crear GitHub Secrets con estos ARNs)."