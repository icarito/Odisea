#!/usr/bin/env python3
"""Post-process a Godot 3 HTML5 export for static hosts.

Godot 3's HTML export normally fetches the raw .pck and .wasm files. Static
hosts such as GitHub Pages do not let this project set Content-Encoding headers
for precompressed files, so this script keeps the originals and adds .gz copies.
It then patches the generated Godot loader to fetch and decompress those .gz
files in browsers with DecompressionStream support, falling back to originals.
"""

from __future__ import annotations

import argparse
import gzip
from pathlib import Path


PATCH_MARKER = "ODISEA_GZIP_EXPORT_PATCH"


HELPER = f"""
\t// {PATCH_MARKER}: prefer precompressed artifacts on static hosts.
\tfunction loadCompressedOrPlain(file) {{
\t\tif (typeof DecompressionStream !== 'function') {{
\t\t\treturn fetch(file);
\t\t}}
\t\tconst gzipFile = `${{file}}.gz`;
\t\treturn fetch(gzipFile).then(function (response) {{
\t\t\tif (!response.ok || !response.body) {{
\t\t\t\tthrow new Error(`Compressed file unavailable: ${{gzipFile}}`);
\t\t\t}}
\t\t\tconst headers = new Headers(response.headers);
\t\t\tif (file.endsWith('.wasm')) {{
\t\t\t\theaders.set('content-type', 'application/wasm');
\t\t\t}} else {{
\t\t\t\theaders.set('content-type', 'application/octet-stream');
\t\t\t}}
\t\t\treturn new Response(response.body.pipeThrough(new DecompressionStream('gzip')), {{
\t\t\t\theaders: headers,
\t\t\t\tstatus: response.status,
\t\t\t\tstatusText: response.statusText,
\t\t\t}});
\t\t}}).catch(function () {{
\t\t\treturn fetch(file);
\t\t}});
\t}}
"""


def gzip_file(path: Path) -> Path:
    out_path = path.with_name(path.name + ".gz")
    with path.open("rb") as src, out_path.open("wb") as raw_dst:
        with gzip.GzipFile(fileobj=raw_dst, mode="wb", compresslevel=9, mtime=0) as dst:
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk:
                    break
                dst.write(chunk)
    return out_path


def patch_loader(index_js: Path) -> None:
    text = index_js.read_text(encoding="utf-8")
    if PATCH_MARKER in text:
        return

    needle = "\n\tfunction loadFetch(file, tracker, fileSize, raw) {\n"
    if needle not in text:
        raise RuntimeError(f"Could not find Godot loader hook in {index_js}")
    text = text.replace(needle, HELPER + needle, 1)

    fetch_needle = "\t\treturn fetch(file).then(function (response) {\n"
    fetch_replacement = "\t\treturn loadCompressedOrPlain(file).then(function (response) {\n"
    if fetch_needle not in text:
        raise RuntimeError(f"Could not find Godot fetch call in {index_js}")
    text = text.replace(fetch_needle, fetch_replacement, 1)

    index_js.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("export_dir", type=Path, help="Directory containing index.html/index.js")
    args = parser.parse_args()

    export_dir = args.export_dir
    index_js = export_dir / "index.js"
    if not index_js.is_file():
        raise SystemExit(f"Missing Godot HTML loader: {index_js}")

    patch_loader(index_js)

    for suffix in (".pck", ".wasm"):
        for path in export_dir.glob(f"*{suffix}"):
            gz_path = gzip_file(path)
            before = path.stat().st_size
            after = gz_path.stat().st_size
            ratio = after / before if before else 0.0
            print(f"{path.name}: {before} -> {gz_path.name}: {after} ({ratio:.1%})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
