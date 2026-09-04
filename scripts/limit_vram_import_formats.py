#!/usr/bin/env python3
"""Reduce Godot 3 VRAM texture variants in a CI export workspace.

Godot writes every generated variant to ``dest_files`` in a texture ``.import``
manifest.  The exporter packages every listed destination, even when the target
platform cannot use that format.  CI caches those manifests, so merely changing
``project.godot`` is not enough to remove stale ETC/PVRTC files from a desktop
PCK.

This script is deliberately non-destructive: it rewrites only the checkout used
for one export job and never deletes cached or tracked ``.stex`` artifacts.
"""

import argparse
import re
from pathlib import Path


PLATFORM_FORMATS = {
	"linux_x64": {"s3tc"},
	"windows": {"s3tc"},
	"macos": {"s3tc"},
	"linux_arm64": {"s3tc", "etc"},
	"android": {"s3tc", "etc", "etc2"},
	# El trim de formatos del workflow genera s3tc (DXT, tras drop_bptc_web_artifacts.py)
	# y etc2; ETC1 no se genera para web, listarlo aca solo dejaba manifests apuntando a un
	# archivo inexistente.
	"html5": {"s3tc", "etc2"},
	"ios": {"s3tc", "etc", "etc2", "pvrtc"},
}

FORMAT_PATTERN = re.compile(r"\.(bptc|s3tc|etc2|etc|pvrtc)\.stex$")
DEST_FILES_PATTERN = re.compile(r"dest_files=\[(.*?)\]", re.DOTALL)
IMPORTED_FORMATS_PATTERN = re.compile(r"\"imported_formats\": \[.*?\](,?)", re.DOTALL)


def _format_for_path(path: str) -> str:
	match = FORMAT_PATTERN.search(path)
	return match.group(1) if match else ""


def _rewrite_manifest(path: Path, allowed_formats: set) -> bool:
	text = path.read_text(encoding="utf-8", errors="ignore")
	if "imported_formats" not in text:
		return False

	lines = []
	for line in text.splitlines(keepends=True):
		match = re.match(r"(path\.(bptc|s3tc|etc2|etc|pvrtc))=", line)
		if match and match.group(2) not in allowed_formats:
			continue
		lines.append(line)
	updated = "".join(lines)

	def _rewrite_dest_files(match: re.Match) -> str:
		paths = re.findall(r'\"([^\"]+)\"', match.group(1))
		kept = [item for item in paths if not _format_for_path(item) or _format_for_path(item) in allowed_formats]
		return "dest_files=[ " + ", ".join('"%s"' % item for item in kept) + " ]"

	updated = DEST_FILES_PATTERN.sub(_rewrite_dest_files, updated)
	formats = ", ".join('"%s"' % item for item in sorted(allowed_formats))
	updated = IMPORTED_FORMATS_PATTERN.sub('"imported_formats": [ %s ]\\1' % formats, updated)
	if updated == text:
		return False
	path.write_text(updated, encoding="utf-8")
	return True


def main() -> int:
	parser = argparse.ArgumentParser(description="Limit cached Godot VRAM formats for one export platform.")
	parser.add_argument("platform", choices=sorted(PLATFORM_FORMATS.keys()))
	parser.add_argument("--project-path", default=".", help="Godot project checkout to normalize.")
	args = parser.parse_args()

	project = Path(args.project_path)
	allowed_formats = PLATFORM_FORMATS[args.platform]
	updated_count = 0
	for manifest in project.rglob("*.import"):
		if not manifest.is_file():
			continue
		if _rewrite_manifest(manifest, allowed_formats):
			updated_count += 1
	print("VRAM import manifests normalized for %s (%s): %d updated" % (
		args.platform, ", ".join(sorted(allowed_formats)), updated_count))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
