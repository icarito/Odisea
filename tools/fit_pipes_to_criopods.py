#!/usr/bin/env python3
"""Recorta los anillos de coolant para que existan solo debajo de los criopods.

Los anillos venian como dos medios toros fijos (West 90-270, East 270-90) que se
TOCABAN en las dos junturas, y eran identicos en los cinco pisos — mientras que
los pods y los huecos del deck cambian piso a piso. Resultado: caño colgando en el
aire sobre las aberturas, y las dos mitades unidas.

Este tool no sintetiza geometria: cada Arc/Joint ya es un PipeSection con su
Transform, asi que solo BORRA las piezas que no van. Se queda con una pieza si:

  1. cae dentro del lado que le toca, con las dos mitades separadas por un side
     completo (West 135-270, East 315-90), y
  2. su tramo se solapa con una corrida de pods del anillo de ese piso.

Correr DESPUES de hornear criopods (lee DomeIntro_Criopods.nodes) y ANTES de
hornear pipes. Verificar con tools/check_criopod_layout.py.

Uso: python3 tools/fit_pipes_to_criopods.py [--dry-run]
"""

import math
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
INTERIORS = RAIZ / "core_v2/levels/interiors"
PIPES = INTERIORS / "DomeIntro_PipeNetworkSource.tscn"
HUB = INTERIORS / "DomeIntro_HubTowerSource.tscn"
FRAGMENTO = INTERIORS / "DomeIntro_Criopods.nodes"

ESCALA_ANILLO = 1.5
PASO_POD = 360.0 / 40          # 9 grados entre slots
ARCO = 15.0                    # cada Arc cubre 15 grados
# Claro de pods que el caño cruza. Va en "todos": lo unico que tiene que cortar el
# caño es la falta de PISO, no la falta de pods. Un claro de pods es el paso de un
# riser o la sombra de un spoke, y cortar ahi partia el circuito en islas que la
# serpentina despues no podia unir (F3 East quedaba en dos tramos disjuntos).
# El extremo de la corrida lo sigue marcando el primer y ultimo pod de esa mitad,
# asi que el caño no se estira mas alla de los criopods.
PUENTE = 32.0
# Las dos mitades se tocaban en las junturas (90 y 270). Se les abre un hueco
# centrado en cada juntura; el ancho es la unica perilla, y es un compromiso: mas
# separacion se lee mejor como dos circuitos, menos deja mas criopods con caño
# debajo. Ver --sep en la ayuda.
JUNTURAS = (90.0, 270.0)
SEPARACION_DEFECTO = 22.5


def lados(sep):
    m = sep / 2.0
    return {"West": (JUNTURAS[0] + m, JUNTURAS[1] - m),
            "East": (JUNTURAS[1] + m, JUNTURAS[0] - m)}


def _norm(a):
    return a % 360.0


def _en_rango(a, lo, hi):
    """Angulo dentro de [lo, hi], envolviendo en 360."""
    a, lo, hi = _norm(a), _norm(lo), _norm(hi)
    return lo <= a <= hi if lo <= hi else (a >= lo or a <= hi)


def coberturas_por_anillo():
    """Criopods<N> -> [(desde, hasta)] de cada corrida de pods, con medio paso."""
    anillo, angs = None, {}
    for m in re.finditer(r'^\[node name="(Criopods\d|Pod_\d+)"[^\]]*\]\n'
                         r'transform = Transform\(([^)]*)\)', FRAGMENTO.read_text(), re.M):
        v = [float(x) for x in m.group(2).split(",")]
        if m.group(1).startswith("Criopods"):
            anillo = int(m.group(1)[-1])
            angs[anillo] = []
        else:
            angs[anillo].append(_norm(math.degrees(math.atan2(
                v[11] * ESCALA_ANILLO, v[9] * ESCALA_ANILLO))))
    salida = {}
    for anillo, lista in angs.items():
        lista.sort()
        corridas, actual = [], [lista[0]]
        for prev, cur in zip(lista, lista[1:]):
            if cur - prev < PASO_POD * 1.5:
                actual.append(cur)
            else:
                corridas.append(actual)
                actual = [cur]
        corridas.append(actual)
        if len(corridas) > 1 and (lista[0] + 360.0) - lista[-1] < PASO_POD * 1.5:
            corridas[0] = corridas[-1] + corridas[0]
            corridas.pop()
        # media separacion a cada punta: el caño llega hasta debajo del ultimo pod
        salida[anillo] = [(c[0] - PASO_POD / 2, c[-1] + PASO_POD / 2) for c in corridas]
    return salida


def _desenrollar(a, lo):
    """Angulo llevado a [lo, lo+360), para poder comparar rangos que cruzan el 0."""
    a, lo = _norm(a), _norm(lo)
    return a + 360.0 if a < lo else a


def huecos_de_deck():
    """Floor_N -> [(desde, hasta)] de los sectores salteados del hub."""
    dentro = r'(?:(?:(?!\[node name="Floor_)[\s\S])*?)'
    salida = {}
    for m in re.finditer(r'^\[node name="(Floor_\d)" parent="ScaffoldHubTower"' + dentro +
                         r'^skipped_sides = \[ ([\d, ]*) \]', HUB.read_text(), re.M | re.S):
        secs = [int(x) for x in m.group(2).split(",") if x.strip()]
        if secs:
            salida[int(m.group(1)[-1])] = [(min(secs) * 45.0, (max(secs) + 1) * 45.0)]
    return salida


def main():
    dry = "--dry-run" in sys.argv
    sep = SEPARACION_DEFECTO
    if "--sep" in sys.argv:
        sep = float(sys.argv[sys.argv.index("--sep") + 1])
    LADOS = lados(sep)
    print("separacion entre mitades: %g deg  (West %g-%g, East %g-%g)" % (
        sep, LADOS["West"][0], LADOS["West"][1], LADOS["East"][0], LADOS["East"][1]))
    cobertura = coberturas_por_anillo()
    deck = huecos_de_deck()
    # Corridas de pods, fusionando los claros chicos (ver PUENTE). Asi el caño cruza
    # el paso del riser pero no se estira por una zona sin criopods.
    tramos = {}
    for anillo, corridas_ in cobertura.items():
        v = sorted(corridas_)
        fus = [list(v[0])]
        for a, b in v[1:]:
            if a - fus[-1][1] <= PUENTE:
                fus[-1][1] = max(fus[-1][1], b)
            else:
                fus.append([a, b])
        # Cierre circular. Tambien cuando quedo UN solo intervalo: ahi el claro que
        # cruza el 0 sigue existiendo (entre el final y el principio del mismo
        # intervalo) y es justo donde estan bloqueados los pods del riser este.
        if (fus[0][0] + 360.0) - fus[-1][1] <= PUENTE:
            if len(fus) > 1:
                fus[0][0] = fus[-1][0] - 360.0
                fus.pop()
            else:
                fus[0] = [fus[0][0] - 360.0, fus[0][1]]
        tramos[anillo - 1] = fus

    texto = PIPES.read_text()

    patron = (r'^\[node name="(Arc\d+|Joint\d+)"[^\n]*'
              r'parent="(\w+/(\w+)_L(\d)_Ring)"[^\n]*\]\n'
              r'(?:(?!\[node)[^\n]*\n)*')
    borrar, resumen, entradas = [], {}, []
    for m in re.finditer(patron, texto, re.M):
        nombre, lado_raw, piso = m.group(1), m.group(3), int(m.group(4))
        mx = re.search(r'transform = Transform\(([^)]*)\)', m.group(0))
        v = [float(x) for x in mx.group(1).split(",")]
        ang = _norm(math.degrees(math.atan2(v[11], v[9])))
        lado = "East" if "East" in lado_raw else "West"

        lo, hi = LADOS[lado]
        media = ARCO / 2 if nombre.startswith("Arc") else 0.0
        # la pieza entera tiene que entrar en su mitad
        dentro = _en_rango(ang - media, lo, hi) and _en_rango(ang + media, lo, hi)
        # Los pods dicen HASTA DONDE llega la corrida, no donde se interrumpe: se usa
        # la extension (primer y ultimo pod de esa mitad), no cada corrida por
        # separado. Copiar los huecos de pods dejaba el caño cortado justo en 0 y 180,
        # que es donde los pods estan bloqueados para darle paso al riser.
        bajo_pods = any(
            d - media <= a <= h + media
            for d, h in tramos.get(piso, []) for a in (ang, ang - 360.0, ang + 360.0))
        # ...salvo donde no hay piso: ahi el caño quedaria en el aire.
        sobre_deck = not any(
            _desenrollar(ang, d) - media < h - 0.01
            and _desenrollar(ang, d) + media > d + 0.01
            for d, h in deck.get(piso, []))

        clave = (piso, lado)
        resumen.setdefault(clave, [0, 0])
        entradas.append({"clave": clave, "nombre": nombre, "ang": ang,
                         "queda": dentro and bajo_pods and sobre_deck,
                         "span": (m.start(), m.end())})

    # Poda hasta punto fijo. Dos reglas, y hay que iterar porque una habilita a la
    # otra: un Joint es un collar ENTRE dos arcos (sin alguno de los dos queda un
    # anillo flotando), y un Arc solo es un tramo de 15 grados suelto en el aire.
    # Borrar un arco puede dejar huerfano a su collar, y viceversa.
    while True:
        arcos = {}
        for e in entradas:
            if e["queda"] and e["nombre"].startswith("Arc"):
                arcos.setdefault(e["clave"], []).append(e["ang"])
        cambio = False
        for e in entradas:
            if not e["queda"]:
                continue
            vecinos = [a for a in arcos.get(e["clave"], []) if a != e["ang"]]
            paso = ARCO if e["nombre"].startswith("Joint") else ARCO * 1.5
            izq = any(-paso < (a - e["ang"] + 180) % 360 - 180 < 0 for a in vecinos)
            der = any(0 < (a - e["ang"] + 180) % 360 - 180 < paso for a in vecinos)
            # el collar necesita los dos lados; el arco, al menos un vecino
            if (izq and der) if e["nombre"].startswith("Joint") else (izq or der):
                continue
            e["queda"] = False
            cambio = True
        if not cambio:
            break

    for e in entradas:
        resumen[e["clave"]][0 if e["queda"] else 1] += 1
        if not e["queda"]:
            borrar.append(e["span"])

    for ini, fin in sorted(borrar, reverse=True):
        texto = texto[:ini] + texto[fin:]

    print("piso lado   quedan  borradas")
    for (piso, lado), (queda, fuera) in sorted(resumen.items()):
        print("  %d  %-5s   %3d      %3d" % (piso, lado, queda, fuera))
    print("\ntotal borradas: %d" % len(borrar))
    if dry:
        print("(dry-run: no escribi nada)")
        return
    PIPES.write_text(texto)
    print("escrito %s" % PIPES.name)


if __name__ == "__main__":
    main()
