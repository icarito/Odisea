#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_fgd="${repo_root}/Qodot.fgd"

if [[ ! -f "${source_fgd}" ]]; then
  echo "Missing canonical FGD: ${source_fgd}" >&2
  exit 1
fi

target_root="${TRENCHBROOM_ODISEA_GAME_DIR:-${HOME}/.TrenchBroom/games/Odisea}"
targets=(
  "${target_root}/Qodot.fgd"
  "${target_root}/Odisea/Qodot.fgd"
)

timestamp="$(date +%Y%m%d-%H%M%S)"

for target in "${targets[@]}"; do
  mkdir -p "$(dirname "${target}")"

  if [[ -e "${target}" && ! -L "${target}" ]]; then
    cp "${target}" "${target}.bak-${timestamp}"
    rm "${target}"
  fi

  ln -sfn "${source_fgd}" "${target}"
  echo "Linked ${target} -> ${source_fgd}"
done

echo "TrenchBroom will pick this up after File > Reload Entity Definitions or restart."
