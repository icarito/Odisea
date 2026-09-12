#!/usr/bin/env python3
"""Genera los assets de una *fuente* PortMaster (API PortMasterV3) para el port
de Odisea, de modo que un dispositivo con PortMaster pueda instalarlo y
actualizarlo solo, sin PR al repo oficial.

    tools/portmaster_source.py <odisea.zip> --base-url <url-del-release> [--out dir]

Escribe en <out> (por defecto el directorio del zip):

    ports.json                    el indice que lee harbourmaster
    <zip sin .zip>.images.zip     la captura, renombrada como la espera el GUI

Ambos se suben como assets del MISMO release que el zip; <base-url> es el
prefijo de descarga de ese release (".../releases/download/nightly").
El ports.json referencia por URL, no por nombre de asset, asi que el zip puede
seguir llamandose Odisea-PortMaster-<version>.zip; lo que tiene que ser estable
es la CLAVE del port ("odisea.zip"), que es como harbourmaster lo identifica.

harbourmaster marca "update available" cuando el md5 del release difiere del
md5 guardado al instalar: con esto cada nightly aparece como actualizacion.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import sys
import zipfile

PORT = "odisea"
PORT_KEY = f"{PORT}.zip"      # la clave que ve harbourmaster; NO el nombre del asset
IMAGES_KEY = "images.zip"     # harbourmaster exige esta clave literal en utils
ROOT = pathlib.Path(__file__).resolve().parent.parent


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("zip", type=pathlib.Path, help="el .zip de PortMaster ya construido")
    ap.add_argument("--base-url", required=True,
                    help="prefijo de descarga del release, sin barra final")
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: hoy, UTC)")
    args = ap.parse_args(argv)

    if not args.zip.is_file() or args.zip.stat().st_size == 0:
        sys.exit(f"ERROR: {args.zip} no existe o esta vacio")

    out = args.out or args.zip.parent
    out.mkdir(parents=True, exist_ok=True)
    base = args.base_url.rstrip("/")
    date = args.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    # La captura viaja en su propio zip, con el nombre <port>.screenshot.png:
    # harbourmaster parsea ese nombre para saber a que port y a que ranura
    # (screenshot/cover/thumbnail) pertenece la imagen.
    screenshot = ROOT / "portmaster" / "screenshot.png"
    images_zip = out / f"{args.zip.stem}.images.zip"
    image_attr = {}
    if screenshot.is_file():
        with zipfile.ZipFile(images_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(screenshot, f"{PORT}.screenshot.png")
        image_attr = {"screenshot": f"{PORT}.screenshot.png"}
    else:
        images_zip = None
        print(f"AVISO: falta {screenshot}, la fuente queda sin captura")

    # El port.json del paquete es la fuente de verdad de los metadatos: el
    # ports.json solo le agrega de donde bajarlo. Se lee del zip y no de
    # portmaster/ para que refleje lo que realmente se empaqueto (build_portmaster.sh
    # reescribe runtime/arch cuando el paquete lleva motor propio).
    with zipfile.ZipFile(args.zip) as zf:
        port_info = json.loads(zf.read(f"{PORT}/port.json"))

    if port_info["name"] != PORT_KEY:
        sys.exit(f"ERROR: port.json declara name={port_info['name']!r}, se esperaba {PORT_KEY!r}")

    port_info["attr"]["image"] = image_attr
    port_info["source"] = {
        "source": "url",
        "date_added": date,
        "date_updated": date,
        "url": f"{base}/{args.zip.name}",
        "size": args.zip.stat().st_size,
        "md5": md5(args.zip),
    }

    utils = {}
    if images_zip is not None:
        utils[IMAGES_KEY] = {
            "name": IMAGES_KEY,
            "url": f"{base}/{images_zip.name}",
            "size": images_zip.stat().st_size,
            "md5": md5(images_zip),
        }

    ports_json = {"ports": {PORT_KEY: port_info}, "utils": utils}

    # Lo que harbourmaster lee sin tolerancia: sin estas claves el port no
    # aparece en la lista o falla la verificacion del md5 al instalar.
    p = ports_json["ports"][PORT_KEY]
    assert ports_json.keys() == {"ports", "utils"}, ports_json.keys()
    assert p["version"] == 4 and p["items"] and p["attr"]["title"], p
    assert p["source"]["url"].startswith("https://"), p["source"]["url"]
    assert p["source"]["size"] > 0 and len(p["source"]["md5"]) == 32
    for u in utils.values():
        assert u["url"].startswith("https://") and len(u["md5"]) == 32, u

    dest = out / "ports.json"
    dest.write_text(json.dumps(ports_json, indent=4) + "\n")
    print(f"{dest}: {PORT_KEY} -> {p['source']['url']} ({p['source']['md5']})")
    if images_zip is not None:
        print(f"{images_zip}: captura para el GUI")
    return 0


if __name__ == "__main__":
    sys.exit(main())
