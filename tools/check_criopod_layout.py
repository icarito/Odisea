#!/usr/bin/env python3
"""Revisa el horneado de criopods contra el patron de huecos del hub.

Tres cosas que no se ven en un diff ni en una foto, y que hay que rehacer cada vez
que cambia `skipped_sides`:

  1. baranda que atraviesa un pod   — el borde radial de un sector salteado se
     cierra con baranda, que cruza justo por donde hay pods
  2. pod suelto                     — un slot que quedo aislado entre dos bloqueos
     contiguos; se ve como un criopod flotando solo en medio de nada
  3. techo sin donde pararse        — una abertura sin deck solido debajo, o sea
     sin forma de subir saltando, que es para lo que estan las aberturas

El patron se lee de DomeIntro_HubTowerSource.tscn, no se repite aca: si cambia
alla, este chequeo cambia solo.

Uso: python3 tools/check_criopod_layout.py    (correr DESPUES de hornear)
"""

import math
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
INTERIORS = RAIZ / "core_v2/levels/interiors"
# Salto que no cruza la cabecera del siguiente Floor_ (ver comentarios abajo).
DENTRO = r'(?:(?:(?!\[node name="Floor_)[\s\S])*?)'
HUB = INTERIORS / "DomeIntro_HubTowerSource.tscn"
PIPES = INTERIORS / "DomeIntro_PipeNetworkSource.tscn"
FRAGMENTO = INTERIORS / "DomeIntro_Criopods.nodes"

ESCALA_ANILLO = 1.5
MEDIA_CAJA = 0.484276 * ESCALA_ANILLO   # medio ancho del pod, en mundo
RADIO_TUBO = 0.07                       # medio diametro del tubo de la baranda
HOLGURA = MEDIA_CAJA + RADIO_TUBO
SLOTS = 40                              # item_count de las rings
PASO = 360.0 / SLOTS


def huecos_por_piso():
    """Floor_N -> [sectores salteados], leido de la fuente del hub."""
    t = HUB.read_text()
    fuera = {}
    for m in re.finditer(r'^\[node name="(Floor_\d)" parent="ScaffoldHubTower"' + DENTRO +
                         r'^skipped_sides = \[ ([\d, ]*) \]', t, re.M | re.S):
        fuera[int(m.group(1)[-1])] = [int(x) for x in m.group(2).split(",") if x.strip()]
    return fuera


def risers():
    """[(angulo, radio)] de los caños verticales de coolant, del source de pipes."""
    salida = []
    for m in re.finditer(r'^\[node name="Valve(West|East)Floor0"[^\n]*\]\n'
                         r'transform = Transform\(([^)]*)\)', PIPES.read_text(), re.M):
        v = [float(x) for x in m.group(2).split(",")]
        salida.append((math.degrees(math.atan2(v[11], v[9])) % 360.0,
                       math.hypot(v[9], v[11])))
    return salida


def pasos_declarados():
    """Floor_N -> [(angulo, radio)] declarados en radial_rail_pass_throughs."""
    t = HUB.read_text()
    salida = {}
    for m in re.finditer(r'^\[node name="(Floor_\d)" parent="ScaffoldHubTower"' + DENTRO +
                         r'^radial_rail_pass_throughs = \[([^\]]*)\]$', t, re.M | re.S):
        salida[int(m.group(1)[-1])] = [
            (float(a), float(b))
            for a, b in re.findall(r'Vector2\( *([-\d.]+), *([-\d.]+) *\)', m.group(2))]
    return salida


def pods_por_anillo():
    """Criopods<N> -> [(x, z) en mundo]. El fragmento guarda espacio del anillo."""
    anillo, salida = None, {}
    for m in re.finditer(r'^\[node name="(Criopods\d|Pod_\d+)"[^\]]*\]\n'
                         r'transform = Transform\(([^)]*)\)', FRAGMENTO.read_text(), re.M):
        v = [float(x) for x in m.group(2).split(",")]
        if m.group(1).startswith("Criopods"):
            anillo = int(m.group(1)[-1])
            salida[anillo] = []
        else:
            salida[anillo].append((v[9] * ESCALA_ANILLO, v[11] * ESCALA_ANILLO))
    return salida


def corridas(angulos):
    """Grupos de pods angularmente contiguos, envolviendo en 360."""
    angulos = sorted(angulos)
    grupos, actual = [], [angulos[0]]
    for prev, cur in zip(angulos, angulos[1:]):
        if cur - prev < PASO * 1.5:
            actual.append(cur)
        else:
            grupos.append(actual)
            actual = [cur]
    grupos.append(actual)
    if len(grupos) > 1 and (angulos[0] + 360.0) - angulos[-1] < PASO * 1.5:
        grupos[0] = grupos[-1] + grupos[0]
        grupos.pop()
    return grupos


def main():
    fuera = huecos_por_piso()
    pods = pods_por_anillo()
    fallas = []

    # 1. baranda atravesando pods. Criopods<N+1> se para sobre Floor_N, y las
    # barandas radiales de ese piso estan en los bordes de sus sectores salteados.
    for piso, sectores in sorted(fuera.items()):
        anillo = piso + 1
        if anillo not in pods or not sectores:
            continue
        peor = 99.0
        for borde in (min(sectores) * 45.0, (max(sectores) + 1) * 45.0):
            a = math.radians(borde)
            for x, z in pods[anillo]:
                if math.cos(a) * x + math.sin(a) * z < 0:
                    continue  # del otro lado del origen, no es esta baranda
                peor = min(peor, abs(-math.sin(a) * x + math.cos(a) * z))
        estado = "ok" if peor >= HOLGURA else "MAL"
        if peor < HOLGURA:
            fallas.append("baranda de Floor_%d atraviesa un pod (%.2f < %.2f m)" % (
                piso, peor, HOLGURA))
        print("  Floor_%d: pod mas cercano a una baranda radial = %.2f m (min %.2f)  %s" % (
            piso, peor, HOLGURA, estado))

    # 1b. baranda radial atravesando un caño vertical. Los risers estan en 180 y 0,
    # que son bordes EXACTOS de la grilla de 45: cualquier hueco que termine ahi
    # pone la baranda justo sobre el caño si no se declara el paso.
    r_in = 6.0 / math.cos(math.radians(22.5))
    r_out = 13.0 / math.cos(math.radians(22.5))
    declarados = pasos_declarados()
    print()
    for piso, sectores in sorted(fuera.items()):
        if not sectores:
            continue
        for borde in (min(sectores) * 45.0, (max(sectores) + 1) * 45.0):
            for ang, radio in risers():
                delta = (ang - borde + 180.0) % 360.0 - 180.0
                if abs(delta) > 90.0 or not (r_in <= radio <= r_out):
                    continue
                if radio * abs(math.sin(math.radians(delta))) >= 0.22:
                    continue
                tiene = any(abs((a - ang + 180) % 360 - 180) < 0.5 and abs(r - radio) < 0.2
                            for a, r in declarados.get(piso, []))
                print("  Floor_%d: baranda radial a %5.1f pasa por un riser (r=%.1f)  %s" % (
                    piso, borde % 360, radio,
                    "paso declarado, ok" if tiene else "SIN DECLARAR"))
                if not tiene:
                    fallas.append(
                        "la baranda radial de Floor_%d a %.0f atraviesa un riser; "
                        "falta radial_rail_pass_throughs" % (piso, borde % 360))

    # 2. pods sueltos
    print()
    for anillo in sorted(pods):
        angs = [math.degrees(math.atan2(z, x)) % 360.0 for x, z in pods[anillo]]
        sueltos = [g[0] for g in corridas(angs) if len(g) == 1]
        if sueltos:
            fallas.append("Criopods%d tiene %d pod(s) suelto(s) en %s" % (
                anillo, len(sueltos), [round(s, 1) for s in sueltos]))
        print("  Criopods%d (Floor_%d): %2d pods, %d corridas, sueltos=%s" % (
            anillo, anillo - 1, len(angs), len(corridas(angs)),
            [round(s, 1) for s in sueltos] or "-"))

    # 3. techo con donde pararse
    print()
    for piso in sorted(fuera):
        arriba = set(fuera[piso])
        abajo = set(fuera.get(piso - 1, []))   # piso 0 = suelo del domo, solido
        pisables = sorted(arriba - abajo)
        if not pisables:
            fallas.append("Floor_%d abre %s pero no hay deck abajo para saltar" % (
                piso, sorted(arriba)))
        print("  %-16s abre %-9s pisable desde abajo %-9s %s" % (
            "suelo->Floor_1" if piso == 1 else "Floor_%d->Floor_%d" % (piso - 1, piso),
            sorted(arriba), pisables, "ok" if pisables else "MAL"))

    # 4. pipes: solo debajo de pods, solo sobre deck solido, y las dos mitades
    # separadas. Se lee el source de pipes ya recortado por fit_pipes_to_criopods.py.
    print()
    piezas = {}
    for m in re.finditer(r'^\[node name="(?:Arc|Joint)\d+"[^\n]*'
                         r'parent="\w+/(\w+)_L(\d)_Ring"[^\n]*\]\n'
                         r'transform = Transform\(([^)]*)\)', PIPES.read_text(), re.M):
        v = [float(x) for x in m.group(3).split(",")]
        piezas.setdefault(int(m.group(2)), []).append(
            ("East" if "East" in m.group(1) else "West",
             math.degrees(math.atan2(v[11], v[9])) % 360.0))

    for piso in sorted(piezas):
        secs = fuera.get(piso, [])
        lo, hi = (min(secs) * 45.0, (max(secs) + 1) * 45.0) if secs else (0.0, 0.0)
        angs = [math.degrees(math.atan2(z, x)) % 360.0 for x, z in pods.get(piso + 1, [])]
        corrs = corridas(angs)
        sobre_hueco, sin_pods = 0, 0
        for lado, ang in piezas[piso]:
            if secs and lo <= (ang if ang >= lo else ang + 360.0) < hi:
                sobre_hueco += 1
            cubierto = any(g[0] - PASO * 1.5 <= a <= g[-1] + PASO * 1.5
                           for g in corrs for a in (ang, ang + 360.0))
            if not cubierto:
                sin_pods += 1
        oeste = [a for l, a in piezas[piso] if l == "West"]
        este = [a for l, a in piezas[piso] if l == "East"]
        sep = min(abs((o - e + 180) % 360 - 180) for o in oeste for e in este) \
            if oeste and este else 999.0
        estado = "ok"
        if sobre_hueco or sin_pods or sep < 15.0:
            estado = "MAL"
            fallas.append("pipes de Floor_%d: %d sobre el hueco, %d sin pods, "
                          "separacion entre mitades %.1f deg" % (
                              piso, sobre_hueco, sin_pods, sep))
        print("  Floor_%d pipes: %2d piezas | sobre hueco=%d | sin pods=%d | "
              "separacion mitades=%.1f deg  %s" % (
                  piso, len(piezas[piso]), sobre_hueco, sin_pods, sep, estado))

    print()
    if fallas:
        for f in fallas:
            print("FALLA: %s" % f)
        sys.exit(1)
    print("[check_criopod_layout] ok")


if __name__ == "__main__":
    main()
