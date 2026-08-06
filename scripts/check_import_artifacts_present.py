#!/usr/bin/env python3
"""Verifica que cada .import trackeado tenga su artefacto generado en disco.

Un `.tscn` que referencia un asset importado (audio, textura, modelo) falla al
cargar con "Make sure resources have been imported..." si el artefacto de
`.import/` no esta presente, aunque el asset fuente y su manifiesto si esten en
git. Eso pasa en CI cuando la cache de `.import/` viene de un commit viejo y el
pase de import no alcanza a procesar los assets nuevos: el fallo aparece despues,
lejos de su causa, como un test que no puede cargar una escena.

Este chequeo corre despues del pase de import (ver `scripts/godot_import_smoke.sh`)
y falla en el paso de import con la lista exacta de assets sin artefacto.

Invariante: cada manifiesto debe tener AL MENOS UNO de sus `dest_files` presente.
No se exigen todos porque las texturas declaran un dest por formato VRAM
(`.s3tc.stex`, `.etc2.stex`, ...) y cada plataforma genera solo el suyo.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Sequence, Set

from check_tracked_imports import (
	RES_PREFIX,
	_parse_manifest,
	_repo_root,
	_res_to_fs,
	_tracked_import_manifests,
	_tracked_paths,
)


DEFAULT_ALLOWLIST_PATH = Path("ci/import_artifacts_allowlist.txt")


def _load_allowlist(repo_root: Path, allowlist_rel: Path) -> Set[str]:
	allowlist_path = repo_root / allowlist_rel
	if not allowlist_path.is_file():
		return set()
	entries: Set[str] = set()
	for raw_line in allowlist_path.read_text(encoding="utf-8").splitlines():
		line = raw_line.strip()
		if not line or line.startswith("#"):
			continue
		entries.add(line)
	return entries


def _manifests_without_artifacts(
	repo_root: Path,
	manifests: Sequence[Path],
	allowlist: Set[str],
) -> tuple[List[tuple[Path, List[str]]], Set[str]]:
	missing: List[tuple[Path, List[str]]] = []
	allowed_hits: Set[str] = set()
	for manifest_rel in manifests:
		_source_file, dest_files = _parse_manifest(repo_root / manifest_rel)
		dests = [dest for dest in dest_files if dest.startswith(RES_PREFIX)]
		if not dests:
			continue
		present = False
		for dest in dests:
			dest_fs = _res_to_fs(repo_root, manifest_rel, dest, False)
			if dest_fs is not None and dest_fs.exists():
				present = True
				break
		if present:
			continue
		key = manifest_rel.as_posix()
		if key in allowlist:
			allowed_hits.add(key)
			continue
		missing.append((manifest_rel, dests))
	return missing, allowed_hits


def main() -> int:
	parser = argparse.ArgumentParser(
		description="Validate that generated import artifacts exist for tracked .import manifests.",
	)
	parser.add_argument(
		"--allowlist",
		default=DEFAULT_ALLOWLIST_PATH.as_posix(),
		help="Path to the allowlist of manifests known to have no generated artifact.",
	)
	parser.add_argument(
		"--suggest-tracking",
		action="store_true",
		help="Print the `git add -f` remediation for the missing artifacts.",
	)
	args = parser.parse_args()

	repo_root = _repo_root()
	manifests = _tracked_import_manifests(repo_root)
	if not manifests:
		print("[import-artifacts] no tracked import manifests to validate")
		return 0

	allowlist = _load_allowlist(repo_root, Path(args.allowlist))
	missing, allowed_hits = _manifests_without_artifacts(repo_root, manifests, allowlist)
	stale_allowlist = sorted(allowlist - allowed_hits)
	if stale_allowlist:
		print("[import-artifacts] allowlist entries no longer needed (%d):" % len(stale_allowlist))
		for entry in stale_allowlist:
			print(" - %s" % entry)

	if not missing:
		print(
			"[import-artifacts] %d manifest(s) validated, %d allowlisted: every asset has an artifact"
			% (len(manifests), len(allowed_hits))
		)
		return 0

	print(
		"[import-artifacts] %d asset(s) have no generated artifact in .import/ (of %d manifest(s))"
		% (len(missing), len(manifests))
	)
	for manifest_rel, dests in missing:
		print(" - %s" % manifest_rel.as_posix())
		for dest in dests:
			print("     esperado: %s" % dest)

	print("")
	print("[import-artifacts] Cualquier escena que referencie estos assets NO va a cargar.")
	if args.suggest_tracking:
		tracked = _tracked_paths(repo_root)
		suggestions = [
			dest[len(RES_PREFIX):]
			for _manifest_rel, dests in missing
			for dest in dests
			if dest[len(RES_PREFIX):] not in tracked
		]
		if suggestions:
			print("[import-artifacts] Reimporte el proyecto, o agregue el artefacto al repo:")
			for dest_rel in suggestions:
				print("    git add -f %s" % dest_rel)
		else:
			print("[import-artifacts] Los artefactos estan trackeados en git pero faltan en disco:")
			print("[import-artifacts] restaure el working tree (`git checkout -- .import`) o reimporte.")
	return 1


if __name__ == "__main__":
	sys.exit(main())
