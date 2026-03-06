#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, List, Sequence, Set

from check_tracked_imports import (
	RES_PREFIX,
	_parse_manifest,
	_repo_root,
	_res_to_fs,
	_run_git_bytes,
	_tracked_paths,
)


DEFAULT_POLICY_PATH = Path("ci/critical_imports.json")


def _load_policy(repo_root: Path, policy_rel: Path) -> List[dict]:
	policy_path = repo_root / policy_rel
	if not policy_path.is_file():
		raise FileNotFoundError("policy missing: %s" % policy_rel.as_posix())
	data = json.loads(policy_path.read_text(encoding="utf-8"))
	entries = data.get("critical_import_manifests", [])
	if not isinstance(entries, list):
		raise ValueError("policy field critical_import_manifests must be a list")
	normalized: List[dict] = []
	for index, raw in enumerate(entries):
		if not isinstance(raw, dict):
			raise ValueError("policy entry %d must be an object" % index)
		manifest_path = raw.get("path")
		if not isinstance(manifest_path, str) or not manifest_path.endswith(".import"):
			raise ValueError("policy entry %d has invalid path" % index)
		sidecars = raw.get("required_sidecars", [])
		if not isinstance(sidecars, list) or any(not isinstance(item, str) for item in sidecars):
			raise ValueError("policy entry %d has invalid required_sidecars" % index)
		reason = raw.get("reason", "")
		if reason and not isinstance(reason, str):
			raise ValueError("policy entry %d has invalid reason" % index)
		normalized.append(
			{
				"path": Path(manifest_path),
				"required_sidecars": list(dict.fromkeys(sidecars)),
				"reason": reason,
			}
		)
	return normalized


def _manifest_dest_relpaths(repo_root: Path, manifest_rel: Path) -> List[Path]:
	source_file, dest_files = _parse_manifest(repo_root / manifest_rel)
	if source_file is None and not dest_files:
		return []
	relpaths: List[Path] = []
	for dest in dest_files:
		if not dest.startswith(RES_PREFIX):
			continue
		relpaths.append(Path(dest[len(RES_PREFIX):]))
	return relpaths


def _critical_related_paths(repo_root: Path, policy_rel: Path, entries: Sequence[dict]) -> Set[Path]:
	paths: Set[Path] = {policy_rel}
	for entry in entries:
		manifest_rel = entry["path"]
		paths.add(manifest_rel)
		manifest_path = repo_root / manifest_rel
		if not manifest_path.is_file():
			continue
		source_file, _dest_files = _parse_manifest(manifest_path)
		if source_file and source_file.startswith(RES_PREFIX):
			paths.add(Path(source_file[len(RES_PREFIX):]))
		for dest_rel in _manifest_dest_relpaths(repo_root, manifest_rel):
			paths.add(dest_rel)
			for suffix in entry["required_sidecars"]:
				paths.add(dest_rel.with_suffix(suffix))
	return paths


def _staged_paths(repo_root: Path) -> Set[Path]:
	output = _run_git_bytes(
		repo_root,
		["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
	)
	return {
		Path(raw.decode("utf-8"))
		for raw in output.split(b"\x00")
		if raw
	}


def _validate_entry(repo_root: Path, tracked_paths: Set[str], entry: dict) -> List[str]:
	errors: List[str] = []
	manifest_rel: Path = entry["path"]
	required_sidecars: Sequence[str] = entry["required_sidecars"]
	manifest_path = repo_root / manifest_rel
	manifest_label = manifest_rel.as_posix()

	if manifest_label not in tracked_paths:
		errors.append("%s: critical manifest is not tracked by git" % manifest_label)
	if not manifest_path.is_file():
		errors.append("%s: critical manifest file is missing" % manifest_label)
		return errors

	source_file, dest_files = _parse_manifest(manifest_path)
	if source_file is None and not dest_files:
		errors.append("%s: importer resolves to keep/empty; should not be listed as critical" % manifest_label)
		return errors
	if not source_file:
		errors.append("%s: missing source_file" % manifest_label)
	else:
		source_fs = _res_to_fs(repo_root, manifest_rel, source_file, True)
		if source_fs is None:
			errors.append("%s: unsupported source path %s" % (manifest_label, source_file))
		elif not source_fs.exists():
			errors.append("%s: missing source %s" % (manifest_label, source_file))

	if not dest_files:
		errors.append("%s: missing dest_files/path entries" % manifest_label)
		return errors

	for dest in dest_files:
		if not dest.startswith(RES_PREFIX):
			errors.append("%s: unsupported critical dest path %s" % (manifest_label, dest))
			continue
		dest_rel = Path(dest[len(RES_PREFIX):])
		dest_label = dest_rel.as_posix()
		dest_fs = _res_to_fs(repo_root, manifest_rel, dest, False)
		if dest_fs is None or not dest_fs.exists():
			errors.append("%s: missing critical artifact %s" % (manifest_label, dest))
			continue
		if dest_label not in tracked_paths:
			errors.append("%s: critical artifact is not tracked %s" % (manifest_label, dest))
		for suffix in required_sidecars:
			sidecar_rel = dest_rel.with_suffix(suffix)
			sidecar_label = sidecar_rel.as_posix()
			sidecar_fs = repo_root / sidecar_rel
			if not sidecar_fs.exists():
				errors.append("%s: missing critical sidecar res://%s" % (manifest_label, sidecar_label))
				continue
			if sidecar_label not in tracked_paths:
				errors.append("%s: critical sidecar is not tracked res://%s" % (manifest_label, sidecar_label))
	return errors


def _print_summary(entries: Iterable[dict], errors: Sequence[str], policy_rel: Path) -> None:
	entry_count = sum(1 for _ in entries)
	if errors:
		print(
			"[critical-imports] validation failed (%d manifest(s), %d issue(s), policy=%s)"
			% (entry_count, len(errors), policy_rel.as_posix())
		)
		for error in errors:
			print(" - %s" % error)
		return
	print(
		"[critical-imports] validated %d critical manifest(s) successfully (policy=%s)"
		% (entry_count, policy_rel.as_posix())
	)


def main() -> int:
	parser = argparse.ArgumentParser(description="Validate tracked artifacts for critical Godot import manifests.")
	parser.add_argument(
		"--policy",
		default=str(DEFAULT_POLICY_PATH),
		help="Relative path to the critical imports policy JSON.",
	)
	parser.add_argument(
		"--staged",
		action="store_true",
		help="Validate only when staged changes touch critical import inputs/artifacts.",
	)
	args = parser.parse_args()

	repo_root = _repo_root()
	policy_rel = Path(args.policy)
	try:
		entries = _load_policy(repo_root, policy_rel)
	except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
		print("[critical-imports] %s" % exc, file=sys.stderr)
		return 1

	if args.staged:
		staged_paths = _staged_paths(repo_root)
		if not staged_paths:
			print("[critical-imports] no staged files to validate")
			return 0
		relevant_paths = _critical_related_paths(repo_root, policy_rel, entries)
		if staged_paths.isdisjoint(relevant_paths):
			print("[critical-imports] no staged critical import paths to validate")
			return 0

	tracked_paths = _tracked_paths(repo_root)
	errors: List[str] = []
	for entry in entries:
		errors.extend(_validate_entry(repo_root, tracked_paths, entry))
	_print_summary(entries, errors, policy_rel)
	return 1 if errors else 0


if __name__ == "__main__":
	sys.exit(main())
