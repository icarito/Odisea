#!/usr/bin/env python3
"""Chequea que los assets importados tengan su artefacto generado disponible en CI.

Contexto (medido, no supuesto):

- El pase de import de CI (`godot --editor --quit`) aborta el scan antes de
  procesar nada nuevo ("Scan thread aborted"): en la practica CI no importa, vive
  de la cache de `.import/` que se fue acumulando. Un asset recien agregado, si su
  artefacto no viaja en el repo, NO existe en CI.
- Un `ext_resource` de audio/escena/malla que no resuelve tumba la escena entera
  ("[ext_resource] referenced nonexistent resource"). Una textura faltante, en
  cambio, solo imprime un error suelto: la escena igual carga. Por eso las
  texturas quedan fuera del chequeo fatal (y ademas son las que pesan).

Modos:

  --mode added --base <sha>   Fatal. Manifiestos AGREGADOS desde <sha> cuyo
                              artefacto no esta trackeado en git. Es la regla que
                              se hace cumplir en CI.
  --mode all                  Informativo. Lista todos los assets sin artefacto en
                              disco, para que el hueco sea visible en el log.
                              Con --strict, falla.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List, Sequence, Set

from check_tracked_imports import (
	RES_PREFIX,
	_parse_manifest,
	_repo_root,
	_res_to_fs,
	_run_git,
	_should_validate_manifest_path,
	_tracked_import_manifests,
	_tracked_paths,
)


DEFAULT_ALLOWLIST_PATH = Path("ci/import_artifacts_allowlist.txt")
# Un .stex faltante no impide cargar la escena que lo usa, y versionarlos es
# justamente lo que la politica de assets evita (ver docs/engineering/CI_Asset_Strategy.md).
TOLERATED_SUFFIXES = (".stex",)


def _load_allowlist(repo_root: Path, allowlist_rel: Path) -> Set[str]:
	allowlist_path = repo_root / allowlist_rel
	if not allowlist_path.is_file():
		return set()
	entries: Set[str] = set()
	for raw_line in allowlist_path.read_text(encoding="utf-8").splitlines():
		line = raw_line.strip()
		if line and not line.startswith("#"):
			entries.add(line)
	return entries


def _dest_files(repo_root: Path, manifest_rel: Path) -> List[str]:
	_source_file, dest_files = _parse_manifest(repo_root / manifest_rel)
	return [dest for dest in dest_files if dest.startswith(RES_PREFIX)]


def _is_tolerated(dests: Sequence[str]) -> bool:
	return bool(dests) and all(dest.endswith(TOLERATED_SUFFIXES) for dest in dests)


def _added_manifests(repo_root: Path, base_sha: str) -> List[Path]:
	output = _run_git(
		repo_root,
		["diff", "--name-only", "--diff-filter=A", base_sha, "HEAD"],
	)
	return sorted(
		Path(line.strip())
		for line in output.splitlines()
		if line.strip().endswith(".import")
		and _should_validate_manifest_path(line.strip())
		and (repo_root / line.strip()).is_file()
	)


def _check_added(repo_root: Path, base_sha: str, allowlist: Set[str]) -> int:
	manifests = _added_manifests(repo_root, base_sha)
	if not manifests:
		print("[import-artifacts] no hay assets importados nuevos desde %s" % base_sha)
		return 0

	tracked = _tracked_paths(repo_root)
	offenders: List[tuple[Path, List[str]]] = []
	for manifest_rel in manifests:
		if manifest_rel.as_posix() in allowlist:
			continue
		dests = _dest_files(repo_root, manifest_rel)
		if not dests or _is_tolerated(dests):
			continue
		if any(dest[len(RES_PREFIX):] in tracked for dest in dests):
			continue
		offenders.append((manifest_rel, dests))

	if not offenders:
		print("[import-artifacts] %d asset(s) importado(s) nuevo(s): todos con artefacto trackeado" % len(manifests))
		return 0

	print("[import-artifacts] %d asset(s) importado(s) nuevo(s) sin artefacto trackeado:" % len(offenders))
	for manifest_rel, _dests in offenders:
		print(" - %s" % manifest_rel.as_posix())
	print("")
	print("[import-artifacts] CI no importa: si el artefacto no viaja en el repo, no existe alla,")
	print("[import-artifacts] y cualquier escena que referencie el asset no carga. Agreguelo:")
	for _manifest_rel, dests in offenders:
		for dest in dests:
			print("    git add -f %s" % dest[len(RES_PREFIX):])
	print("")
	print("[import-artifacts] (Si el asset es deliberadamente prescindible, listelo en %s.)" % DEFAULT_ALLOWLIST_PATH.as_posix())
	return 1


def _check_all(repo_root: Path, allowlist: Set[str], strict: bool, fail_on_missing_textures: bool = False) -> int:
	manifests = _tracked_import_manifests(repo_root)
	missing: List[tuple[Path, List[str]]] = []
	for manifest_rel in manifests:
		if manifest_rel.as_posix() in allowlist:
			continue
		dests = _dest_files(repo_root, manifest_rel)
		if not dests:
			continue
		present = any(
			(_res_to_fs(repo_root, manifest_rel, dest, False) or Path("/nonexistent")).exists()
			for dest in dests
		)
		if not present:
			missing.append((manifest_rel, dests))

	if not missing:
		print("[import-artifacts] %d manifiesto(s): todos con artefacto en disco" % len(manifests))
		return 0

	# Las texturas se toleran por defecto: un .stex ausente no tumba la escena en
	# CI (ver docs/engineering/CI_Asset_Strategy.md). --fail-on-missing-textures
	# lo activa para el pipeline de export real, donde SI importa: un lightmap sin
	# .stex se empaqueta en blanco y nadie se entera hasta verlo en el dispositivo.
	blocking = [
		(rel, dests) for rel, dests in missing
		if not _is_tolerated(dests) or fail_on_missing_textures
	]
	print(
		"[import-artifacts] %d asset(s) sin artefacto en disco (%d texturas tolerables, %d no)"
		% (len(missing), len(missing) - len(blocking), len(blocking))
	)
	for manifest_rel, dests in missing:
		mark = "textura" if _is_tolerated(dests) else "ROMPE ESCENAS"
		print(" - [%s] %s" % (mark, manifest_rel.as_posix()))
	if not strict:
		print("[import-artifacts] informativo: no falla el paso (ver docs/engineering/CI_Asset_Strategy.md)")
		return 0
	return 1 if blocking else 0


def main() -> int:
	parser = argparse.ArgumentParser(
		description="Validate that imported assets have their generated artifact available to CI.",
	)
	parser.add_argument("--mode", choices=["added", "all"], default="all")
	parser.add_argument("--base", help="Base commit for --mode added.")
	parser.add_argument("--strict", action="store_true", help="Make --mode all fail on blocking gaps.")
	parser.add_argument(
		"--fail-on-missing-textures",
		action="store_true",
		help="Don't tolerate missing .stex in --mode all --strict (for real export pipelines, not the CI smoke test).",
	)
	parser.add_argument("--allowlist", default=DEFAULT_ALLOWLIST_PATH.as_posix())
	args = parser.parse_args()

	repo_root = _repo_root()
	allowlist = _load_allowlist(repo_root, Path(args.allowlist))
	if args.mode == "added":
		if not args.base:
			parser.error("--mode added requiere --base <sha>")
		try:
			_run_git(repo_root, ["rev-parse", "--verify", "%s^{commit}" % args.base])
		except subprocess.CalledProcessError:
			print("[import-artifacts] base %s no disponible en este checkout; se omite el chequeo" % args.base)
			return 0
		return _check_added(repo_root, args.base, allowlist)
	return _check_all(repo_root, allowlist, args.strict, args.fail_on_missing_textures)


if __name__ == "__main__":
	sys.exit(main())
