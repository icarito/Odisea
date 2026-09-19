#!/usr/bin/env python3
"""Agrega una fuente de fallback a todos los DynamicFont del proyecto.

Godot 3 resuelve un glifo faltante recorriendo `fallback/N` del DynamicFont.
Con una sola fuente de respaldo que cubra Hangul + Latin-1 completo, el coreano
deja de salir como tofu y de paso se cubren los 13 acentos que le faltan a
Ac437_OlivettiThin (los de portugues: a/o con tilde, etc.).

Es idempotente: si el DynamicFont ya tiene un `fallback/`, no lo toca.

    python3 tools/add_font_fallback.py            # aplica
    python3 tools/add_font_fallback.py --check    # solo reporta, exit 1 si falta
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FALLBACK_TTF = "res://assets/fonts/DungGeunMo.ttf"
SKIP_DIRS = {"addons", ".git", ".import", ".venv", ".kilo", "node_modules", "dashboard"}

HEADER_RE = re.compile(r'^\[gd_(?:scene|resource)\b.*?\bload_steps=(\d+)', re.M)
EXT_RE = re.compile(r'^\[ext_resource path="([^"]+)" type="([^"]+)" id=(\d+)\]', re.M)
BLOCK_RE = re.compile(
    r'^\[(sub_resource type="DynamicFont" id=\d+|resource)\]\n((?:(?!\[)[^\n]*\n)*)', re.M)


def iter_files():
    for path in REPO.rglob("*"):
        if path.suffix not in (".tres", ".tscn"):
            continue
        if any(part in SKIP_DIRS or part.startswith(".") for part in path.relative_to(REPO).parts[:-1]):
            continue
        yield path


def patch(text, is_root_dynamicfont):
    """Devuelve (texto_nuevo, n_fallbacks_agregados)."""
    blocks = []
    for m in BLOCK_RE.finditer(text):
        head, body = m.group(1), m.group(2)
        if head == "resource" and not is_root_dynamicfont:
            continue
        if "fallback/" in body:
            continue
        if "font_data" not in body:
            continue
        blocks.append(m)
    if not blocks:
        return text, 0

    # ext_resource para la fuente de respaldo (reutiliza si ya esta)
    ext_id = None
    used = set()
    for m in EXT_RE.finditer(text):
        used.add(int(m.group(3)))
        if m.group(1) == FALLBACK_TTF:
            ext_id = int(m.group(3))
    added_ext = ext_id is None
    if added_ext:
        ext_id = max(used) + 1 if used else 1
        line = '[ext_resource path="%s" type="DynamicFontData" id=%d]\n' % (FALLBACK_TTF, ext_id)
        if used:  # insertar tras el ultimo ext_resource
            at = list(EXT_RE.finditer(text))[-1].end() + 1
        else:  # tras la cabecera, dejando la linea en blanco de separacion
            at = text.index("\n", text.index("[gd_")) + 2
            line += "\n"
        text = text[:at] + line + text[at:]
        h = HEADER_RE.search(text)
        text = text[:h.start(1)] + str(int(h.group(1)) + 1) + text[h.end(1):]

    # re-buscar los bloques sobre el texto ya desplazado
    added = 0
    for m in reversed(list(BLOCK_RE.finditer(text))):
        head, body = m.group(1), m.group(2)
        if head == "resource" and not is_root_dynamicfont:
            continue
        if "fallback/" in body or "font_data" not in body:
            continue
        # al final del bloque, pero antes de la linea en blanco que lo separa
        trailing = len(body) - len(body.rstrip("\n"))
        at = m.end(2) - max(0, trailing - 1)
        text = text[:at] + "fallback/0 = ExtResource( %d )\n" % ext_id + text[at:]
        added += 1
    return text, added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    pending = []
    for path in iter_files():
        text = path.read_text(encoding="utf-8")
        if 'DynamicFont"' not in text:
            continue
        is_root = text.startswith('[gd_resource type="DynamicFont"')
        new, added = patch(text, is_root)
        if added:
            pending.append((path.relative_to(REPO), added))
            if not args.check:
                path.write_text(new, encoding="utf-8")

    for rel, n in pending:
        print(("FALTA" if args.check else "fallback+") + " %-60s %d" % (rel, n))
    print("%d fuentes %s" % (sum(n for _, n in pending), "sin fallback" if args.check else "parcheadas"))
    return 1 if (args.check and pending) else 0


if __name__ == "__main__":
    sys.exit(main())
