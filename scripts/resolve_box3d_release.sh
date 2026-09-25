#!/usr/bin/env bash
#
# resolve_box3d_release.sh — Devuelve el release del fork Box3D (icarito/godot-box3d-3)
# MAS NUEVO por fecha de publicación, incluyendo nightlies/pre-releases. Se usa en el
# canal nightly de Odisea para que cada nightly tome automáticamente el último engine
# del fork. El canal release/CI sigue usando el pin .github/box3d_release.
#
# Uso:  BOX3D_RELEASE="$(scripts/resolve_box3d_release.sh)"
# Env:  BOX3D_FORK_REPO (default: icarito/godot-box3d-3)
#
# Sin `gh` cae a la API pública de GitHub (sin auth, rate-limited). Si todo falla,
# imprime el pin y sale 0 (nunca rompe un build por un hipo de red).
set -euo pipefail

REPO="${BOX3D_FORK_REPO:-icarito/godot-box3d-3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "$HERE/.github/box3d_release" 2>/dev/null || true)"

TAG=""
if command -v gh >/dev/null 2>&1; then
  # gh ya excluye drafts; ordenamos por publishedAt desc. Los pre-releases (nightlies)
  # se incluyen a propósito.
  TAG="$(gh release list -R "$REPO" --limit 50 --json tagName,publishedAt \
    -q 'sort_by(.publishedAt) | reverse | .[0].tagName' 2>/dev/null || true)"
fi

if [ -z "$TAG" ]; then
  TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=50" 2>/dev/null \
    | python3 -c 'import sys,json
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
releases = [r for r in data if not r.get("draft")]
releases.sort(key=lambda r: r.get("published_at") or "")
print(releases[-1]["tag_name"] if releases else "")' 2>/dev/null || true)"
fi

[ -n "$TAG" ] || TAG="$PIN"
echo "$TAG"
