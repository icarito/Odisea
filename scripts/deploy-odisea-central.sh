#!/usr/bin/env bash
# Deploy odisea-central desde el repo Odisea y reinicia el servicio.
# Incluye el build del frontend React Dashboard.
# Uso: ./scripts/deploy-odisea-central.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="/home/ubuntu/anna-central"
BRANCH="anna2" # Cambiar a "merge-fd-130-131-164-166" si aún no se hace merge a anna2
SERVICE="odisea-central.service"

echo "==> Actualizando repo ($BRANCH)..."
cd "$REPO_DIR"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

echo "==> Construyendo frontend React (Dashboard)..."
cd "$REPO_DIR/dashboard"
npm ci
npm run build

echo "==> Desplegando archivos..."
# Copiar el script principal actualizado
cp "$REPO_DIR/odisea_central.py" "$DEPLOY_DIR/odisea_central.py"

# Copiar el directorio static con los assets compilados del dashboard
mkdir -p "$DEPLOY_DIR/static"
rm -rf "$DEPLOY_DIR/static/dashboard"
cp -r "$REPO_DIR/dashboard/dist" "$DEPLOY_DIR/static/dashboard"

# Asegurar permisos
chown -R ubuntu:ubuntu "$DEPLOY_DIR"

echo "==> Reiniciando $SERVICE..."
sudo systemctl restart "$SERVICE"
sleep 2

if systemctl is-active --quiet "$SERVICE"; then
  echo "==> OK: $SERVICE activo."
  sudo journalctl -u "$SERVICE" -n 5 --no-pager
else
  echo "!! ERROR: $SERVICE no quedó activo. Revisa los logs:"
  sudo journalctl -u "$SERVICE" -n 20 --no-pager
  exit 1
fi
