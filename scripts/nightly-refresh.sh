#!/bin/bash
# Refresca el nightly.json del landing de Odisea desde GitHub Releases.
#
# Dos modos:
#   (sin args)  un intento; si la release y sus assets no son consistentes
#               (publicacion a medias), NO toca el JSON y sale 1.
#   --watch     reintenta hasta ~15 min cada 45s hasta que la release esta
#               completa; para el webhook release.* (el evento edited llega
#               ANTES de que terminen los uploads).
# El cron cada 5 min sigue como red de seguridad con el modo sin args.
set -u
MODE="${1:-}"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

attempt () {
  if ! curl -fsS --max-time 20 \
      https://api.github.com/repos/icarito/Odisea/releases/tags/nightly -o "$TMP"; then
    return 1
  fi
  python3 - "$TMP" <<'PY'
import json, os, re, sys, tempfile
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
m = re.search(r"\d+\.\d+\.\d+-nightly\.\d+\+[0-9a-f]+", d.get("name", ""))
if not m:
    sys.exit(1)
version = m.group(0)
pats = {
    "linux": r"^Odisea-Tech-Demo-Linux-\d.*\.zip$",
    "windows": r"^Odisea-Tech-Demo-Windows-\d.*\.zip$",
    "android": r"^Odisea-Tech-Demo-Android-\d.*\.apk$",
}
urls, sizes = {}, {}
for key, pat in pats.items():
    asset = next(
        (a for a in d.get("assets", [])
         if re.match(pat, a["name"]) and version in a["name"]),
        None,
    )
    if asset:
        urls[key] = asset["browser_download_url"]
        sizes[key] = "~%d MB" % round(asset["size"] / (1024 * 1024))
# El publish edita la release ANTES de subir assets y borra los viejos al
# final: si falta una plataforma o el asset no coincide con la version, es
# una publicacion a medias -> mantener el JSON previo (exit 1, sin escribir).
if len(urls) < 3:
    sys.exit(1)
out = {
    "version": version,
    "urls": urls,
    "sizes": sizes,
    "release_updated": d.get("updated_at"),
}
outpath = "/var/www/odisea-landing/nightly.json"
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(outpath))
with os.fdopen(fd, "w") as f:
    json.dump(out, f, indent=1)
os.chmod(tmp, 0o644)
os.replace(tmp, outpath)
PY
}

if [ "$MODE" = "--watch" ]; then
  for _ in $(seq 1 20); do
    if attempt; then
      exit 0
    fi
    sleep 45
  done
  echo "nightly-refresh: inconsistent tras 20 intentos, se mantiene el JSON previo" >&2
  exit 1
fi

attempt
