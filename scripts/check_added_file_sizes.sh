#!/usr/bin/env bash
set -euo pipefail

# Fail when newly added files exceed the max size (default: 50 MB).
# Existing tracked large files are ignored.

MAX_BYTES="${MAX_BYTES:-52428800}"
BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

if [[ -z "${BASE_REF}" ]]; then
  echo "Usage: $0 <base-ref> [head-ref]"
  echo "Example: $0 origin/main HEAD"
  exit 2
fi

mapfile -t added_files < <(git diff --name-only --diff-filter=A "${BASE_REF}" "${HEAD_REF}")

if [[ "${#added_files[@]}" -eq 0 ]]; then
  echo "No added files detected between ${BASE_REF} and ${HEAD_REF}."
  exit 0
fi

failed=0
for path in "${added_files[@]}"; do
  [[ -f "${path}" ]] || continue
  size="$(wc -c < "${path}")"
  if (( size > MAX_BYTES )); then
    mb="$(awk "BEGIN {printf \"%.2f\", ${size}/1024/1024}")"
    echo "ERROR: ${path} is ${mb} MB (limit: 50.00 MB)"
    failed=1
  fi
done

if (( failed )); then
  exit 1
fi

echo "OK: No newly added file exceeds 50 MB."
