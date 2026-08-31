#!/usr/bin/env python3
"""Convierte los grupos de caneria de Dome_Intro a PipeRoute (kit modular).

Cada PipeCoolantRun tiene hoy decenas de hijos con Transform explicito (Arc, Joint,
RiserSeg, Junction, SerpentineTurn): 1518 lineas que nadie puede editar a mano. Esto
recupera la POLILINEA que esas piezas describen —encadenandolas por sus extremos— y
las reemplaza por un solo nodo PipeRoute con la lista de puntos.

NO se toca ningun nodo de logica. Las ~24 fugas apuntan por NodePath a su corrida
(`../TowerCoolantRiser_L2_Ring`), y esos nodos siguen existiendo con el mismo nombre:
la ruta va ADENTRO como hijo, y PipeCoolantRun._assign_to_meshes() recursa, asi que
igual les pinta el material.

Uso: python3 tools/migrate_pipes_to_routes.py [--dry-run]
"""

import math
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
PIPES = RAIZ / "core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
RUTA_SCRIPT = "res://core_v2/props/pipe/kit/PipeRoute.gd"
# Piezas de geometria; todo lo demas (fugas, parches, valvulas) se deja intacto.
# Los Joint son COLLARES que se apoyan sobre la junta entre dos arcos: comparten
# extremo con los dos y vuelven ambiguo el encadenado (la cadena se parte en cada
# collar). La polilinea sale de los tramos que avanzan; los collares se descartan,
# el kit ya resuelve la junta.
GEOMETRIA = re.compile(r'^(Section|Arc|RiserSeg|Junction|SerpentineTurn)')
DESCARTAR = re.compile(r'^Joint')


def leer_piezas(texto):
    """grupo -> [(nombre, inicio, fin, span_en_el_texto)] de sus piezas de geometria."""
    grupos = {}
    sueltos = []
    patron = (r'^\[node name="([^"]+)"[^\n]*parent="([^"]*)"[^\n]*'
              r'instance=ExtResource\( \d \)\]\ntransform = Transform\(([^)]*)\)\n')
    for m in re.finditer(patron, texto, re.M):
        nombre, padre = m.group(1), m.group(2)
        if DESCARTAR.match(nombre):
            grupos.setdefault(padre, [])
            sueltos.append((m.start(), m.end()))
            continue
        if not GEOMETRIA.match(nombre):
            continue
        v = [float(x) for x in m.group(3).split(",")]
        o = (v[9], v[10], v[11])
        x = (v[0], v[3], v[6])
        a = tuple(o[i] - x[i] for i in range(3))
        b = tuple(o[i] + x[i] for i in range(3))
        grupos.setdefault(padre, []).append((nombre, a, b, (m.start(), m.end())))
    return grupos, sueltos


def encadenar(piezas, tol=0.35):
    """Ordena las piezas en una polilinea siguiendo extremos que coinciden.

    Devuelve la lista de puntos. Si el grupo esta partido en varios tramos devuelve
    el mas largo y avisa: un tramo suelto no deberia entrar en la misma ruta.
    """
    restantes = list(piezas)
    cadenas = []
    while restantes:
        nombre, a, b, _ = restantes.pop(0)
        cadena = [a, b]
        cambio = True
        while cambio:
            cambio = False
            for i, (_, ca, cb) in enumerate([(p[0], p[1], p[2]) for p in restantes]):
                for extremo, otro in ((ca, cb), (cb, ca)):
                    if math.dist(cadena[-1], extremo) < tol:
                        cadena.append(otro)
                        restantes.pop(i)
                        cambio = True
                        break
                    if math.dist(cadena[0], extremo) < tol:
                        cadena.insert(0, otro)
                        restantes.pop(i)
                        cambio = True
                        break
                if cambio:
                    break
        cadenas.append(cadena)
    cadenas.sort(key=len, reverse=True)
    # Los tramos verticales del riser se SOLAPAN 2 m entre si (miden 6.5 y van cada
    # 4.5), asi que no encadenan punta a punta aunque formen una columna continua.
    # Si todo el grupo es colineal, la polilinea es una sola recta de extremo a
    # extremo.
    puntos = [p for c in cadenas for p in c]
    if len(cadenas) > 1 and _colineales(puntos):
        ejes = list(zip(*puntos))
        lo = min(puntos, key=lambda q: (q[0], q[1], q[2]))
        hi = max(puntos, key=lambda q: (q[0], q[1], q[2]))
        return [[lo, hi]]
    return cadenas


def _colineales(pts, tol=0.02):
    if len(pts) < 3:
        return True
    base = pts[0]
    dirs = [[q[k] - base[k] for k in range(3)] for q in pts[1:]]
    ref = max(dirs, key=lambda d: sum(c * c for c in d))
    nref = math.sqrt(sum(c * c for c in ref))
    if nref < 1e-6:
        return True
    for d in dirs:
        nd = math.sqrt(sum(c * c for c in d))
        if nd < 1e-6:
            continue
        cos = abs(sum(d[k] * ref[k] for k in range(3)) / (nd * nref))
        if cos < 1.0 - tol:
            return False
    return True


def simplificar(pts, tol=0.02):
    """Saca los puntos intermedios colineales: dos rectos seguidos son un recto."""
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        pa = [pts[i][k] - out[-1][k] for k in range(3)]
        pb = [pts[i + 1][k] - pts[i][k] for k in range(3)]
        na = math.sqrt(sum(c * c for c in pa))
        nb = math.sqrt(sum(c * c for c in pb))
        if na < 1e-6 or nb < 1e-6:
            continue
        cos = sum(pa[k] * pb[k] for k in range(3)) / (na * nb)
        if cos < 1.0 - tol:
            out.append(pts[i])
    out.append(pts[-1])
    return out


def main():
    dry = "--dry-run" in sys.argv
    texto = PIPES.read_text()

    # El alta del ext_resource va ANTES de leer las piezas. Insertarlo despues corre
    # todos los offsets ya calculados, y las borradas terminan cortando dentro de
    # otras lineas: eso dejo la escena ilegible dos veces (un
    # "use_local_axis_override = true" partido a la mitad). El orden es contrato.
    m = re.search(r'^\[ext_resource path="%s"[^\]]*id=(\d+)\]' % re.escape(RUTA_SCRIPT),
                  texto, re.M)
    if m:
        route_id = int(m.group(1))
    else:
        ids = [int(x) for x in re.findall(r'^\[ext_resource[^\]]*id=(\d+)\]', texto, re.M)]
        route_id = max(ids) + 1
        cab = re.search(r'^\[ext_resource[^\n]*\]\n', texto, re.M)
        texto = texto[:cab.end()] + (
            '[ext_resource path="%s" type="Script" id=%d]\n' % (RUTA_SCRIPT, route_id)
        ) + texto[cab.end():]

    grupos, collares = leer_piezas(texto)
    borrar, nuevos, avisos = [], [], []
    for grupo, piezas in sorted(grupos.items()):
        cadenas = encadenar(piezas)
        # Una ruta POR CADENA. Un grupo puede tener tramos legitimamente separados
        # (las cuatro vueltas de la serpentina son verticales a angulos distintos);
        # meterlos en una sola polilinea inventaria cano entre ellos.
        emitidas = 0
        for cadena in cadenas:
            pts = simplificar(cadena)
            if len(pts) < 2:
                continue
            plano = ", ".join("%g" % c for pt in pts for c in pt)
            sufijo = "" if emitidas == 0 else str(emitidas + 1)
            nuevos.append('\n[node name="Route%s" type="Spatial" parent="%s"]\n'
                          'script = ExtResource( %d )\n'
                          'puntos = PoolVector3Array( %s )\n'
                          % (sufijo, grupo, route_id, plano))
            emitidas += 1
        if emitidas == 0:
            continue
        for p in piezas:
            borrar.append(p[3])
        print("  %-46s %3d piezas -> %d ruta(s), %s puntos" % (
            grupo, len(piezas), emitidas,
            "+".join(str(len(simplificar(c))) for c in cadenas if len(simplificar(c)) >= 2)))

    # Los collares (Joint) tambien se van: el kit resuelve la junta, y ademas son
    # los que hacian que PipeCoolantRun generase un _EntryCollar de Ø0.46 sobre un
    # cano de Ø0.10.
    borrar += collares
    # Fusionar solapes antes de cortar: dos spans que se pisan, borrados por
    # separado, se llevan puesto texto que no pertenece a ninguno de los dos.
    fusion = []
    for a, b in sorted(borrar):
        if fusion and a <= fusion[-1][1]:
            fusion[-1] = (fusion[-1][0], max(fusion[-1][1], b))
        else:
            fusion.append((a, b))
    for ini, fin in reversed(fusion):
        texto = texto[:ini] + texto[fin:]
    texto = texto.rstrip("\n") + "\n" + "".join(nuevos)

    print("\ngrupos convertidos: %d | piezas borradas: %d" % (len(nuevos), len(borrar)))
    for a in avisos:
        print("AVISO: %s" % a)
    if dry:
        print("(dry-run: no escribi nada)")
        return
    PIPES.write_text(texto)
    print("escrito %s" % PIPES.name)


if __name__ == "__main__":
    main()
