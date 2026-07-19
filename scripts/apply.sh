#!/bin/bash
# ============================================================================
# apply.sh - terraform apply desde el tfplan generado por plan.sh
# ============================================================================
# Uso:
#   ./scripts/apply.sh          # aplica el plan previo (default dev)
#   ./scripts/apply.sh dev      # explicito
#
# Requiere:
#   - Haber corrido plan.sh (existe tfplan en live/dev/)
# ============================================================================
set -euo pipefail

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

if [ ! -d "${LIVE_DIR}" ]; then
  echo "[ERROR] Directorio ${LIVE_DIR} no existe." >&2
  exit 1
fi

cd "${LIVE_DIR}"

if [ ! -f "tfplan" ]; then
  echo "[ERROR] tfplan no existe. Correr plan.sh primero:" >&2
  echo "        ./scripts/plan.sh ${ENV}" >&2
  exit 1
fi

echo "=========================================="
echo "  terraform apply (env=${ENV})"
echo "=========================================="
echo "  Working dir: ${LIVE_DIR}"
echo "  Plan:        tfplan (corregir primero si hay cambios)"
echo ""

terraform apply -input=false tfplan
echo ""
echo "[OK] Apply completo. Para limpiar el tfplan:"
echo "     rm ${LIVE_DIR}/tfplan"