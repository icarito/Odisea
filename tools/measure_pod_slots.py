#!/usr/bin/env python3
"""Mide los slots de criopods por piso (azimut mundial) desde la fuente.

De aca salen los huecos donde puede pasar la serpentina: verticales y puntas
de arco tienen que caer en ventanas sin pod, con margen.

Uso: python3 tools/measure_pod_slots.py [--margen 5.0]
"""
import math
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SRC = RAIZ / "core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn"

# Radio mundial del anillo de pods (local 8.0 x escala 1.5) y medio ancho de
# la caja del pod en metros -> medio ancho angular en grados a esa distancia.
RADIO = 12.0
MEDIO_ANCHO = 0.484276 * 1.5


def azimut(x, z):
    return math.degrees(math.atan2(z, x)) % 360.0


def main():
    margen = 5.0
    if "--margen" in sys.argv:
        margen = float(sys.argv[sys.argv.index("--margen") + 1])
    texto = SRC.read_text()
    pisos = {}
    for m in re.finditer(
        r'\[node name="(Criopods\d)" type="Spatial" parent="Spatial"\]\n'
        r'transform = Transform\(([^)]*)\)[^\[]*?'
        r'(?:\[node name="Item_(\d+)"[^\n]*\]\n'
        r'transform = Transform\(([^)]*)\)\n)+',
        texto, re.S,
    ):
        pass  # el regex anidado no rinde; se parsea por bloques abajo

    # parseo por bloques: cada [node name="CriopodsN"] hasta el proximo [node
    for m in re.finditer(r'\[node name="(Criopods\d)" type="Spatial" parent="Spatial"\]\n([\s\S]*?)(?=\[node name="Criopods\d"|\Z)', texto):
        nombre, bloque = m.group(1), m.group(2)
        piso = int(nombre[-1])
        cab = re.search(r'transform = Transform\(([^)]*)\)', bloque)
        v = [float(x) for x in cab.group(1).split(",")]
        # basis columnas: X=(v0,v3,v6), origen=(v9,v10,v11); escala uniforme 1.5
        # y rot_y=180 estan dentro de la basis; el origen da la altura del piso.
        base_y = v[10]
        esc = abs(v[0])
        slots = []
        for it in re.finditer(r'\[node name="Item_(\d+)"[^\n]*\]\ntransform = Transform\(([^)]*)\)', bloque):
            idx = int(it.group(1))
            t = [float(x) for x in it.group(2).split(",")]
            # origen local (v9,v10,v11) escalado+rotado por la basis del padre:
            # mundo = basis * local + origen. Solo xz importa para el azimut.
            lx, lz = t[9] * esc, t[11] * esc
            wx = v[0] * lx + v[3] * 0.0 + v[6] * lz + v[9]
            wz = v[2] * lx + v[5] * 0.0 + v[8] * lz + v[11]
            slots.append((idx, round(azimut(wx, wz), 2)))
        slots.sort(key=lambda s: s[1])
        pisos[piso] = (base_y, slots)

    for piso in sorted(pisos):
        base_y, slots = pisos[piso]
        azs = [a for _, a in slots]
        huecos = []
        for i in range(len(azs)):
            a, b = azs[i], azs[(i + 1) % len(azs)]
            paso = (b - a) % 360.0
            if paso > 9.0 + 0.01:
                huecos.append((round(a, 1), round((a + paso) % 360.0, 1)))
        print("Piso %d  base_y=%.2f  pods=%d" % (piso, base_y, len(azs)))
        print("  slots: %s" % ", ".join("%.1f" % a for a in azs))
        print("  huecos (>9gr): %s" % huecos)
        libres = []
        for a, b in huecos:
            libre = (a + margen, b - margen)
            if libre[1] > libre[0]:
                libres.append((round(libre[0], 1), round(libre[1], 1)))
        print("  libres con margen %.1fgr: %s" % (margen, libres))
        print()


if __name__ == "__main__":
    main()
