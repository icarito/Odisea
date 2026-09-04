#!/usr/bin/env python3
"""Borra del checkout los artefactos de textura BPTC para que el web los reimporte como DXT.

Por que hace falta
------------------
El proyecto importa con ``vram_compression/import_bptc=true``: la variante "de escritorio"
de cada textura se guarda como **BPTC**, aunque el archivo se llame ``*.s3tc.stex`` (en
Godot 3 BPTC y S3TC comparten ese slot).

Ningun navegador expone ``EXT_texture_compression_bptc``. Y Godot elige el slot de
escritorio en cuanto el driver anuncia S3TC — que es lo que hace WebGL2 —, asi que en el
build web carga un BPTC que no puede subir:

    ERROR: Condition "image->is_compressed()" is true. Returned: image
       at: _get_gl_image_and_format (drivers/gles3/rasterizer_storage_gles3.cpp:531)

Resultado: la textura no sube y el material se dibuja sin ella. No cae a la variante ETC:
ya eligio el slot.

El workflow ya pone ``bptc=False`` para html5 antes de importar, pero eso solo no alcanza:
CI restaura el cache de ``.import/`` y Godot no reimporta una textura cuyo fuente no
cambio, por mas que hayan cambiado los flags. Hay que borrarle el artefacto y su ``.md5``
para que lo regenere; el paso de import del workflow hace el resto.

Solo borra lo que de verdad es BPTC, asi que en cuanto el cache tiene DXT las corridas
siguientes no borran nada y el import queda en no-op.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# Image::Format de Godot 3: 22..24 son las variantes BPTC.
BPTC_FORMATS = {22, 23, 24}
FORMAT_MASK = 0xFFFFF  # los bits altos son flags (mipmaps, stream, detect_*)


def formato_de(stex: Path) -> int | None:
    try:
        with stex.open("rb") as fh:
            cab = fh.read(20)
    except OSError:
        return None
    if len(cab) < 20 or cab[:4] != b"GDST":
        return None
    return struct.unpack("<I", cab[16:20])[0] & FORMAT_MASK


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--import-dir", default=".import")
    ap.add_argument("--dry-run", action="store_true", help="solo listar, no borrar")
    args = ap.parse_args()

    raiz = Path(args.import_dir)
    if not raiz.is_dir():
        print("[bptc] no existe %s; nada que hacer" % raiz)
        return 0

    afectadas = []
    for stex in sorted(raiz.glob("*.s3tc.stex")):
        if formato_de(stex) in BPTC_FORMATS:
            afectadas.append(stex)

    if not afectadas:
        print("[bptc] ninguna textura del slot de escritorio esta en BPTC; nada que borrar")
        return 0

    borrados = 0
    for stex in afectadas:
        base = str(stex)[: -len(".s3tc.stex")]
        # Todas las variantes de esa textura mas su .md5: sin borrar el .md5 Godot la da
        # por importada y no la regenera.
        hermanos = set(Path(raiz).glob(Path(base).name + ".*"))
        hermanos.add(Path(base + ".md5"))
        for h in sorted(hermanos):
            if not h.exists():
                continue
            if args.dry_run:
                print("[bptc] (dry-run) borraria %s" % h)
            else:
                h.unlink()
            borrados += 1

    print("[bptc] %d texturas en BPTC -> %d archivos %s"
          % (len(afectadas), borrados, "listados" if args.dry_run else "borrados"))
    print("[bptc] el paso de import las va a regenerar como DXT con los flags ya recortados")
    return 0


if __name__ == "__main__":
    sys.exit(main())
