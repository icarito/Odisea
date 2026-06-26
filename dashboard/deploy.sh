#!/usr/bin/env bash
# Deploy del dashboard (Vite PWA) a producción.
#
#   build  ->  rsync a staging  ->  swap atómico  ->  restart  ->  verificación
#
# Uso:   ./deploy.sh            (desde src/dashboard/)
#
# - Atómico: el dashboard vivo solo se reemplaza una vez que el build nuevo
#   ya está completo en el servidor. Si algo falla antes del swap, prod no se toca.
# - Backup: el dashboard anterior queda en `dashboard.old` para rollback inmediato.
# - scene-data: el del servidor manda (es data subida, no parte del frontend);
#   nunca se pisa con el snapshot del repo.
#
# Rollback manual:
#   ssh ubuntu@odisea.educa.juegos 'cd /home/ubuntu/anna-central/static
#     mv dashboard dashboard.bad && mv dashboard.old dashboard
#     sudo systemctl restart odisea-central.service'
set -euo pipefail

HOST="${ODISEA_DEPLOY_HOST:-ubuntu@odisea.educa.juegos}"
URL="${ODISEA_DEPLOY_URL:-https://odisea.educa.juegos}"
STATIC="/home/ubuntu/anna-central/static"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"

cd "$(dirname "$0")"

VERSION="$(git rev-parse --short=12 HEAD 2>/dev/null || echo dev)"

echo "==> Build (version $VERSION)"
VITE_DASHBOARD_VERSION="$VERSION" VITE_GIT_COMMIT="$VERSION" pnpm build

echo "==> Subiendo a staging ($HOST)"
rsync -az --delete -e "$SSH" dist/ "$HOST:$STATIC/.dashboard.stage/"

echo "==> Swap atómico + restart (scene-data de prod es autoritativo)"
$SSH "$HOST" "set -e
  cd '$STATIC'
  rm -rf .dashboard.stage/scene-data
  [ -d dashboard/scene-data ] && cp -a dashboard/scene-data .dashboard.stage/scene-data || true
  rm -rf dashboard.old
  [ -d dashboard ] && mv dashboard dashboard.old
  mv .dashboard.stage dashboard
  sudo systemctl restart odisea-central.service"

echo "==> Verificando"
sleep 2
$SSH "$HOST" "
  curl -s --retry 15 --retry-delay 2 --retry-connrefused -o /dev/null -w 'index   %{http_code}\n' '$URL/'
  curl -s -o /dev/null -w 'sw.js   %{http_code}\n' '$URL/sw.js'
  curl -s -o /dev/null -w 'health  %{http_code}\n' '$URL/health'"

echo "==> Listo: $URL  (version $VERSION)"
