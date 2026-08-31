#!/usr/bin/env python3
"""Vista rapida de una variante del modulo de criogenia, SIN hornear.

Hornear una variante tarda minutos y escribe decenas de artefactos; para decidir
que sector sacar no hace falta nada de eso. Los generadores (ScaffoldHubRing,
RadialScatter) reconstruyen en runtime si se les pide, asi que esta vista arma una
escena temporal con las fuentes de la variante, fuerza el rebuild y saca fotos.
Lo que se ve es el .tscn fuente tal cual esta AHORA, horneado o no.

Cada fuente que la variante no tenga cae a la de Dome_Intro, igual que
`make bake-dome-variant`.

Uso: python3 tools/preview_dome_variant.py DomeDefault [--angles 20,110,200,290]
"""

import argparse
import os
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
INTERIORS = RAIZ / "core_v2/levels/interiors"
# Las fuentes que comparten espacio: el hub, lo que se le conecta, lo que se le
# para encima, y los caños que corren debajo. Los pipes entran desde que siguen la
# disposicion de los criopods: su coherencia se mira aca.
FUENTES = ["HubTower", "Scaffold", "Criopods", "PipeNetwork"]


def resolver(variante, nombre):
    propia = INTERIORS / ("%s_%sSource.tscn" % (variante, nombre))
    return propia if propia.exists() else INTERIORS / ("DomeIntro_%sSource.tscn" % nombre)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variante")
    ap.add_argument("--angles", default="20,110,200,290")
    ap.add_argument("--out", default="/tmp/preview")
    args = ap.parse_args()

    temporales = []
    ext, nodos = [], []
    for i, nombre in enumerate(FUENTES, start=1):
        origen = resolver(args.variante, nombre)
        if not origen.exists():
            sys.exit("no encuentro fuente para %s" % nombre)
        # El .tscn fuente guarda los hijos ya horneados de la ULTIMA vez; sin forzar
        # el rebuild la vista mostraria esa geometria vieja y no lo que se acaba de
        # editar. Se fuerza sobre una copia para no ensuciar la fuente.
        # ScaffoldHubRing y RadialScatter comparten el nombre de la bandera. Se
        # engancha a una propiedad que solo esos generadores declaran, y que cada
        # nodo generado tiene exactamente una vez.
        texto = re.sub(r'^(outer_openings_deg = .*|item_count = .*)$',
                       r'\1\nrebuild_baked_items = true',
                       origen.read_text(), flags=re.M)
        copia = INTERIORS / ("_preview_%s.tscn" % nombre)
        copia.write_text(texto)
        temporales.append(copia)
        ext.append('[ext_resource path="res://%s" type="PackedScene" id=%d]'
                   % (copia.relative_to(RAIZ), i))
        nodos.append('[node name="%s" parent="." instance=ExtResource( %d )]' % (nombre, i))

    escena = INTERIORS / "_preview_variant.tscn"
    escena.write_text("[gd_scene load_steps=%d format=2]\n\n%s\n\n[node name=\"Preview\" type=\"Spatial\"]\n\n%s\n"
                      % (len(FUENTES) + 1, "\n".join(ext), "\n\n".join(nodos)))
    temporales.append(escena)

    entorno = dict(os.environ,
                   ODISEA_SHOT_SCENE="res://%s" % escena.relative_to(RAIZ),
                   ODISEA_SHOT_OUT="%s_%s" % (args.out, args.variante),
                   ODISEA_SHOT_TARGETS="HubTower",
                   ODISEA_SHOT_ANGLES=args.angles,
                   ODISEA_SHOT_NOISOLATE="1")
    try:
        salida = subprocess.run(
            [os.environ.get("GODOT", "godot3-bin"), "--path", str(RAIZ), "--no-window",
             "-s", "tools/shot_scaffold.gd"],
            env=entorno, cwd=RAIZ, capture_output=True, text=True)
    finally:
        for f in temporales:
            f.unlink(missing_ok=True)

    fotos = [l for l in salida.stdout.splitlines() if l.startswith("SHOT:")]
    for l in fotos:
        print(l)
    if not fotos:
        print(salida.stdout[-2000:], file=sys.stderr)
        print(salida.stderr[-2000:], file=sys.stderr)
        sys.exit("la vista no produjo fotos")


if __name__ == "__main__":
    main()
