#!/usr/bin/env python3
"""Valida que los presets de exportacion no diverjan entre plataformas.

Los 8 presets comparten el mismo contenido: lo unico que cambia por plataforma
son los formatos VRAM, y de eso ya se encarga el workflow en tiempo de export
(scripts/limit_vram_import_formats.py). Cuando `include_filter`, `exclude_filter`
o `export_files` se separan, el resultado es una plataforma a la que le falta
algo y nadie se entera hasta que un jugador abre la escena.

Ademas revisa dos formas de podredumbre silenciosa:

* Artefactos de ``.import/`` pineados por hash en un filtro. El hash depende de
  los parametros de import; si la textura se reimporta, la entrada apunta a un
  archivo que ya no existe y deja de aportar sin dar error.
* Raices de ``export_files`` que ya no existen en disco. Godot las ignora sin
  chistar, asi que una escena renombrada se lleva su raiz a la tumba.

Lo que este check NO puede ver: que una escena viva falte como raiz de
export_files. Entra igual por los globs de include_filter, pero los globs NO
caminan dependencias -- solo las raices lo hacen -- asi que se empaqueta la
escena sin parte de lo que necesita. Si agregas una escena jugable, agregala
tambien a export_files.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List

PRESET_RE = re.compile(r'^\[preset\.(\d+)\]\s*$', re.M)
NAME_RE = re.compile(r'^name="([^"]*)"', re.M)
FILTER_RE = {
	"include_filter": re.compile(r'^include_filter="([^"]*)"', re.M),
	"exclude_filter": re.compile(r'^exclude_filter="([^"]*)"', re.M),
}
FILES_RE = re.compile(r'^export_files=PoolStringArray\((.*?)\)\s*$', re.M | re.S)
QUOTED_RE = re.compile(r'"([^"]+)"')
PINNED_RE = re.compile(r'\.import/\S+\.(?:stex|scn|mesh|sample|res)\b')


def _presets(text: str) -> Dict[str, Dict[str, object]]:
	"""Corta el .cfg en bloques [preset.N] y extrae lo que nos importa."""
	out: Dict[str, Dict[str, object]] = {}
	marks = [(m.group(1), m.start()) for m in PRESET_RE.finditer(text)]
	for i, (idx, start) in enumerate(marks):
		end = marks[i + 1][1] if i + 1 < len(marks) else len(text)
		body = text[start:end]
		name_m = NAME_RE.search(body)
		if not name_m:
			continue
		entry: Dict[str, object] = {"name": name_m.group(1)}
		for key, rx in FILTER_RE.items():
			m = rx.search(body)
			entry[key] = m.group(1) if m else None
		files_m = FILES_RE.search(body)
		entry["export_files"] = QUOTED_RE.findall(files_m.group(1)) if files_m else None
		out[idx] = entry
	return out


def _check_coherencia(presets: Dict[str, Dict[str, object]]) -> List[str]:
	errors: List[str] = []
	for campo in ("include_filter", "exclude_filter", "export_files"):
		variantes: Dict[str, List[str]] = {}
		for entry in presets.values():
			valor = entry[campo]
			clave = "\n".join(valor) if isinstance(valor, list) else str(valor)
			variantes.setdefault(clave, []).append(str(entry["name"]))
		if len(variantes) > 1:
			grupos = " | ".join(", ".join(sorted(v)) for v in variantes.values())
			errors.append("%s difiere entre presets: %s" % (campo, grupos))
	return errors


def _check_pineados(presets: Dict[str, Dict[str, object]]) -> List[str]:
	errors: List[str] = []
	for entry in presets.values():
		for campo in ("include_filter", "exclude_filter"):
			valor = entry[campo]
			if not isinstance(valor, str):
				continue
			for hit in PINNED_RE.findall(valor):
				errors.append(
					"%s: %s pinea un artefacto de .import/ por hash (%s); "
					"usa la ruta del fuente" % (entry["name"], campo, hit)
				)
	return errors


def _check_orden_y_existencia(presets: Dict[str, Dict[str, object]], root: Path) -> List[str]:
	errors: List[str] = []
	for entry in presets.values():
		files = entry["export_files"]
		if not isinstance(files, list):
			errors.append("%s: no tiene export_files" % entry["name"])
			continue
		if files != sorted(files):
			# Godot lo reescribe ordenado; dejarlo desordenado hace que el editor
			# genere un diff de 300 lineas la proxima vez que toque el archivo.
			errors.append("%s: export_files no esta ordenado alfabeticamente" % entry["name"])
		for res in files:
			if not res.startswith("res://"):
				errors.append("%s: raiz sin prefijo res:// (%s)" % (entry["name"], res))
				continue
			if not (root / res[len("res://"):]).exists():
				errors.append("%s: raiz inexistente en disco (%s)" % (entry["name"], res))
	return errors


def _self_test() -> int:
	def bloque(idx, name, inc, files):
		return ('[preset.%d]\nname="%s"\ninclude_filter="%s"\nexclude_filter="docs/*"\n'
		        'export_files=PoolStringArray( %s )\n'
		        % (idx, name, inc, ', '.join('"%s"' % f for f in files)))

	sano = bloque(0, "A", "*.gd", ["res://a.tscn", "res://b.tscn"]) + \
	       bloque(1, "B", "*.gd", ["res://a.tscn", "res://b.tscn"])
	p = _presets(sano)
	assert len(p) == 2, p
	assert _check_coherencia(p) == []
	assert _check_pineados(p) == []

	divergente = bloque(0, "A", "*.gd", ["res://a.tscn"]) + \
	             bloque(1, "B", "*.tres", ["res://a.tscn", "res://b.tscn"])
	errs = _check_coherencia(_presets(divergente))
	assert len(errs) == 2, errs                       # include_filter y export_files

	pineado = bloque(0, "A", "*.gd, .import/x.png-deadbeef.s3tc.stex", ["res://a.tscn"])
	assert _check_pineados(_presets(pineado)), "debe cazar el artefacto pineado"

	desordenado = bloque(0, "A", "*.gd", ["res://z.tscn", "res://a.tscn"])
	errs = _check_orden_y_existencia(_presets(desordenado), Path("/nonexistent"))
	assert any("ordenado" in e for e in errs), errs
	assert any("inexistente" in e for e in errs), errs

	print("[export-presets] self-test OK")
	return 0


def main() -> int:
	if "--self-test" in sys.argv:
		return _self_test()

	root = Path(__file__).resolve().parent.parent
	cfg = root / "export_presets.cfg"
	if not cfg.is_file():
		print("[export-presets] no se encontro %s" % cfg)
		return 1

	text = cfg.read_text(encoding="utf-8")
	presets = _presets(text)
	if not presets:
		print("[export-presets] no se pudo leer ningun [preset.N]")
		return 1

	errors = (
		_check_coherencia(presets)
		+ _check_pineados(presets)
		+ _check_orden_y_existencia(presets, root)
	)

	if errors:
		print("[export-presets] %d problema(s) en %d presets:" % (len(errors), len(presets)))
		for e in errors:
			print("  - %s" % e)
		return 1

	n_files = len(presets[next(iter(presets))]["export_files"] or [])
	print("[export-presets] OK: %d presets coherentes, %d raices de exportacion"
	      % (len(presets), n_files))
	return 0


if __name__ == "__main__":
	sys.exit(main())
