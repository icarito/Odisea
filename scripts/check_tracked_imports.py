#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, List, Sequence, Set


SOURCE_RE = re.compile(r'^source_file="([^"]+)"')
DEST_RE = re.compile(r'^dest_files=\[(.*)\]')
PATH_RE = re.compile(r'^path="([^"]+)"')
QUOTED_RE = re.compile(r'"([^"]+)"')
RES_PREFIX = "res://"
INCLUDED_ROOTS = (
	"assets/",
	"textures/",
	"models/",
	"scenes/",
	"data/",
	"core_v2/",
)
EXCLUDED_ROOTS = (
	"addons/",
	"test_output/",
)


def _run_git(repo_root: Path, args: Sequence[str]) -> str:
	result = subprocess.run(
		["git", "-C", str(repo_root)] + list(args),
		check=True,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
		text=True,
	)
	return result.stdout


def _run_git_bytes(repo_root: Path, args: Sequence[str]) -> bytes:
	result = subprocess.run(
		["git", "-C", str(repo_root)] + list(args),
		check=True,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
	)
	return result.stdout


def _repo_root() -> Path:
	output = subprocess.run(
		["git", "rev-parse", "--show-toplevel"],
		check=True,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
		text=True,
	)
	return Path(output.stdout.strip())


def _tracked_import_manifests(repo_root: Path) -> List[Path]:
	output = _run_git(repo_root, ["ls-files", "--", "*.import"])
	return sorted(
		Path(line.strip())
		for line in output.splitlines()
		if _should_validate_manifest_path(line.strip()) and (repo_root / line.strip()).is_file()
	)


def _staged_import_manifests(repo_root: Path) -> List[Path]:
	output = _run_git_bytes(
		repo_root,
		["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
	)
	manifests: Set[Path] = set()
	for raw in output.split(b"\x00"):
		if not raw:
			continue
		rel_path = Path(raw.decode("utf-8"))
		if rel_path.suffix == ".import":
			if _should_validate_manifest_path(rel_path.as_posix()):
				manifests.add(rel_path)
			continue
		candidate = Path(str(rel_path) + ".import")
		if _should_validate_manifest_path(candidate.as_posix()) and (repo_root / candidate).is_file():
			manifests.add(candidate)
	return sorted(manifests)

def _should_validate_manifest_path(path: str) -> bool:
	if not path.endswith(".import"):
		return False
	for excluded_root in EXCLUDED_ROOTS:
		if path.startswith(excluded_root):
			return False
	for included_root in INCLUDED_ROOTS:
		if path.startswith(included_root):
			return True
	return False


def _res_to_fs(repo_root: Path, manifest_rel: Path, res_path: str, allow_manifest_relative: bool = False) -> Path | None:
	if not res_path.startswith(RES_PREFIX):
		return None
	relative_path = Path(res_path[len(RES_PREFIX):])
	root_candidate = repo_root / relative_path
	if root_candidate.exists() or not allow_manifest_relative:
		return root_candidate
	current_dir = (repo_root / manifest_rel).parent
	while True:
		manifest_candidate = current_dir / relative_path
		if manifest_candidate.exists():
			return manifest_candidate
		if current_dir == repo_root:
			return root_candidate
		current_dir = current_dir.parent


def _parse_manifest(manifest_path: Path) -> tuple[str | None, List[str]]:
	source_file = None
	dest_files: List[str] = []
	in_remap = False
	importer_name = ""
	for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
		line = raw_line.strip()
		if line.startswith("[") and line.endswith("]"):
			in_remap = line == "[remap]"
			continue
		if line.startswith("importer="):
			importer_name = line.split("=", 1)[1].strip().strip('"')
			continue
		source_match = SOURCE_RE.match(line)
		if source_match:
			source_file = source_match.group(1)
			continue
		dest_match = DEST_RE.match(line)
		if dest_match:
			dest_files.extend(QUOTED_RE.findall(dest_match.group(1)))
			continue
		if in_remap:
			path_match = PATH_RE.match(line)
			if path_match:
				remap_path = path_match.group(1)
				if remap_path not in dest_files:
					dest_files.append(remap_path)
	if importer_name == "keep":
		return None, []
	return source_file, list(dict.fromkeys(dest_files))


def _tracked_paths(repo_root: Path) -> Set[str]:
	output = _run_git(repo_root, ["ls-files"])
	return set(line.strip() for line in output.splitlines() if line.strip())


def _validate_manifest(repo_root: Path, tracked_paths: Set[str], manifest_rel: Path) -> List[str]:
	errors: List[str] = []
	manifest_path = repo_root / manifest_rel
	if not manifest_path.is_file():
		return ["manifest missing: %s" % manifest_rel.as_posix()]
	source_file, dest_files = _parse_manifest(manifest_path)
	if source_file is None and not dest_files:
		return []
	if not source_file:
		errors.append("%s: missing source_file" % manifest_rel.as_posix())
	else:
		source_fs = _res_to_fs(repo_root, manifest_rel, source_file, True)
		if source_fs is None:
			errors.append("%s: unsupported source path %s" % (manifest_rel.as_posix(), source_file))
		elif not source_fs.exists():
			errors.append("%s: missing source %s" % (manifest_rel.as_posix(), source_file))
	if not dest_files:
		errors.append("%s: missing dest_files/path entries" % manifest_rel.as_posix())
	for dest in dest_files:
		dest_fs = _res_to_fs(repo_root, manifest_rel, dest, False)
		if dest_fs is None:
			errors.append("%s: unsupported dest path %s" % (manifest_rel.as_posix(), dest))
		elif dest[len(RES_PREFIX):] in tracked_paths and not dest_fs.exists():
			errors.append("%s: missing dest %s" % (manifest_rel.as_posix(), dest))
	return errors


def _print_summary(manifests: Iterable[Path], errors: Sequence[str]) -> None:
	manifest_count = sum(1 for _ in manifests)
	if errors:
		print("[tracked-imports] validation failed (%d manifest(s), %d issue(s))" % (manifest_count, len(errors)))
		for error in errors:
			print(" - %s" % error)
		return
	print("[tracked-imports] validated %d manifest(s) successfully" % manifest_count)


def main() -> int:
	parser = argparse.ArgumentParser(description="Validate tracked Godot .import manifests and generated artifacts.")
	parser.add_argument(
		"--staged",
		action="store_true",
		help="Validate only manifests related to staged files.",
	)
	args = parser.parse_args()

	repo_root = _repo_root()
	manifests = _staged_import_manifests(repo_root) if args.staged else _tracked_import_manifests(repo_root)
	if not manifests:
		scope = "staged" if args.staged else "tracked"
		print("[tracked-imports] no %s import manifests to validate" % scope)
		return 0

	tracked_paths = _tracked_paths(repo_root)
	errors: List[str] = []
	for manifest_rel in manifests:
		errors.extend(_validate_manifest(repo_root, tracked_paths, manifest_rel))
	_print_summary(manifests, errors)
	return 1 if errors else 0


if __name__ == "__main__":
	sys.exit(main())
