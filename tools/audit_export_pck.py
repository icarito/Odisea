#!/usr/bin/env python3
"""Audit a Godot 3 PCK after export.

The desktop targets must contain only S3TC VRAM texture variants.  This checks
the *packaged* files, which catches stale import-cache manifests that source
configuration checks cannot see.
"""

import argparse
import struct
from collections import Counter
from pathlib import Path


PCK_HEADER_SIZE = 0x54
FORBIDDEN_DESKTOP_SUFFIXES = (".bptc.stex", ".etc.stex", ".etc2.stex", ".pvrtc.stex")


def _read_entries(path: Path) -> list:
	with path.open("rb") as stream:
		if stream.read(4) != b"GDPC":
			raise ValueError("not a Godot PCK")
		stream.seek(PCK_HEADER_SIZE)
		count = struct.unpack("<I", stream.read(4))[0]
		entries = []
		for _index in range(count):
			path_length = struct.unpack("<I", stream.read(4))[0]
			name = stream.read(path_length).decode("utf-8").rstrip("\0")
			offset, size = struct.unpack("<QQ", stream.read(16))
			stream.seek(16, 1)  # MD5
			entries.append((name, size))
	return entries


def main() -> int:
	parser = argparse.ArgumentParser(description="Audit the contents of a Godot 3 PCK.")
	parser.add_argument("pck", type=Path)
	parser.add_argument("--desktop", action="store_true", help="Fail if mobile-only VRAM variants are packaged.")
	args = parser.parse_args()

	entries = _read_entries(args.pck)
	variant_bytes = Counter()
	for name, size in entries:
		for suffix in (".s3tc.stex",) + FORBIDDEN_DESKTOP_SUFFIXES:
			if name.endswith(suffix):
				variant_bytes[suffix] += size
				break
	print("PCK audit: %d entries, %.2f MiB" % (len(entries), args.pck.stat().st_size / 1024 / 1024))
	for suffix, size in sorted(variant_bytes.items()):
		print("  %s: %.2f MiB" % (suffix, size / 1024 / 1024))

	if args.desktop:
		forbidden = [(name, size) for name, size in entries if name.endswith(FORBIDDEN_DESKTOP_SUFFIXES)]
		if forbidden:
			print("ERROR: desktop PCK contains %d mobile/non-desktop VRAM variants:" % len(forbidden))
			for name, _size in forbidden[:20]:
				print("  " + name)
			return 1
	print("PCK audit: PASS")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
