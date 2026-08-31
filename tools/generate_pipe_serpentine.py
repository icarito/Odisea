#!/usr/bin/env python3
"""Genera los tramos verticales que convierten los anillos por piso en una S.

Hoy cada piso cuelga de un riser de altura completa via una T (PipeTee). Eso trae
tres problemas medidos: la T clipea (su brazo de +-7.5 grados queda ENTERO dentro
del primer Arc), varias T tienen un brazo al aire, y el circuito no se puede seguir
con el ojo porque se ramifica en cada piso.

Una serpentina no se ramifica: el caño llega a la punta de un arco, sube, y vuelve
en sentido contrario por el piso de arriba. Todas las uniones son codos.

La vuelta solo puede ir donde los DOS pisos tienen caño en el mismo angulo, asi que
el tool calcula el solape y elige, para cada par, el extremo mas lejano de la vuelta
anterior (asi la S barre lo mas posible). Si un par no se solapa lo informa y deja
la cadena partida en vez de inventar un tramo colgando.

Correr DESPUES de fit_pipes_to_criopods.py.

Uso: python3 tools/generate_pipe_serpentine.py [--dry-run]
"""

import math
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
PIPES = RAIZ / "core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
RADIO = 12.0
ALTURAS = {1: 4.08, 2: 8.58, 3: 13.08, 4: 17.58, 5: 22.08}
GRUPO = {"West": "TowerCoolantRiser", "East": "TowerCoolantRiserEast"}
ID_PIPE_SECTION = 1


def extremos(texto=None):
    """(piso, lado) -> {angulo redondeado: (x, y, z)} de las PUNTAS de cada pieza.

    La vuelta tiene que apoyarse en una punta real, no en un angulo calculado: los
    Arc estan centrados en 7.5+15k y sus puntas caen en los multiplos de 15, asi que
    apuntar al centro del arco deja el tramo vertical colgando en el aire (fue
    exactamente el error de la primera version).
    """
    t = PIPES.read_text() if texto is None else texto
    salida = {}
    for m in re.finditer(r'^\[node name="(?:Arc|Joint)\d+"[^\n]*'
                         r'parent="\w+/(\w+)_L(\d)_Ring"[^\n]*\]\n'
                         r'transform = Transform\(([^)]*)\)', t, re.M):
        v = [float(x) for x in m.group(3).split(",")]
        o = (v[9], v[10], v[11])
        x = (v[0], v[3], v[6])
        lado = "East" if "East" in m.group(1) else "West"
        for sg in (-1.0, 1.0):
            e = tuple(o[i] + sg * x[i] for i in range(3))
            ang = math.degrees(math.atan2(e[2], e[0])) % 360.0
            if lado == "East" and ang > 180.0:
                ang -= 360.0
            salida.setdefault((int(m.group(2)), lado), {})[round(ang, 1)] = e
    return salida


def cobertura():
    """(piso, lado) -> [(desde, hasta)] de tramos continuos de caño, en grados."""
    t = PIPES.read_text()
    crudo = {}
    for m in re.finditer(r'^\[node name="(?:Arc|Joint)\d+"[^\n]*'
                         r'parent="\w+/(\w+)_L(\d)_Ring"[^\n]*\]\n'
                         r'transform = Transform\(([^)]*)\)', t, re.M):
        v = [float(x) for x in m.group(3).split(",")]
        lado = "East" if "East" in m.group(1) else "West"
        ang = math.degrees(math.atan2(v[11], v[9])) % 360.0
        if lado == "East" and ang > 180.0:
            ang -= 360.0
        crudo.setdefault((int(m.group(2)), lado), []).append(ang)
    salida = {}
    for k, angs in crudo.items():
        v = sorted(angs)
        tramos, cur = [], [v[0], v[0]]
        for a in v[1:]:
            if a - cur[1] <= 7.6:
                cur[1] = a
            else:
                tramos.append(tuple(cur))
                cur = [a, a]
        tramos.append(tuple(cur))
        salida[k] = tramos
    return salida


def solape(a, b):
    out = []
    for a1, b1 in a:
        for a2, b2 in b:
            d, h = max(a1, a2), min(b1, b2)
            if h >= d:
                out.append((d, h))
    return out


def xform(ang_deg, p0, p1):
    """PipeSection vertical que va EXACTAMENTE de la punta p0 a la punta p1.

    El eje X del prefab es el largo del tramo; se lo pone vertical y se completa la
    base con la radial hacia adentro y su perpendicular, manteniendo mano derecha.
    """
    a = math.radians(ang_deg)
    c, s = math.cos(a), math.sin(a)
    h = (p1[1] - p0[1]) / 2.0
    o = ((p0[0] + p1[0]) / 2.0, (p0[1] + p1[1]) / 2.0, (p0[2] + p1[2]) / 2.0)
    return "Transform( %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g )" % (
        0.0, -c, -s,
        h, 0.0, 0.0,
        0.0, -s, c,
        o[0], o[1], o[2])


def main():
    dry = "--dry-run" in sys.argv
    ext = extremos()
    texto = PIPES.read_text()
    nuevos, rotos = [], []

    for lado in ("West", "East"):
        previa = None
        for n in range(1, 5):
            aqui, arriba = ext.get((n, lado), {}), ext.get((n + 1, lado), {})
            # una punta que exista en LOS DOS pisos: ahi el tramo vertical apoya
            comunes = sorted(set(aqui) & set(arriba))
            if not comunes:
                rotos.append("%s F%d->F%d: ningun extremo comun" % (lado, n, n + 1))
                previa = None
                continue
            giro = (max(comunes, key=lambda x: abs(x - previa))
                    if previa is not None else max(comunes))
            nuevos.append((lado, n, giro, aqui[giro], arriba[giro]))
            previa = giro

    bloques = []
    for lado, n, giro, abajo, arriba in nuevos:
        bloques.append(
            '\n[node name="SerpentineTurn%d" parent="%s" instance=ExtResource( %d )]\n'
            'transform = %s\n' % (n, GRUPO[lado], ID_PIPE_SECTION,
                                  xform(giro, abajo, arriba)))

    # Las T que la serpentina reemplaza. Se van con su bloque entero.
    quitadas = 0
    for m in list(re.finditer(r'^\[node name="Junction\w+"[^\n]*instance=ExtResource\( 2 \)\]\n'
                              r'(?:(?!\[node)[^\n]*\n)*', texto, re.M))[::-1]:
        texto = texto[:m.start()] + texto[m.end():]
        quitadas += 1

    texto = texto.rstrip("\n") + "\n" + "".join(bloques)

    # Poda de islas: un tramo que quedo separado del circuito por un hueco de deck
    # no se puede unir sin cruzar el agujero. Unas pocas piezas sueltas bajo dos o
    # tres pods se leen peor que no tener caño ahi.
    islas = 0
    for _ in range(8):
        pz = []
        for m in re.finditer(r'^\[node name="([^"]+)"[^\n]*'
                             r'parent="(TowerCoolantRiser(?:East)?[^"]*)"[^\n]*'
                             r'instance=ExtResource\( 1 \)\]\n'
                             r'transform = Transform\(([^)]*)\)\n', texto, re.M):
            v = [float(x) for x in m.group(3).split(",")]
            o, x = (v[9], v[10], v[11]), (v[0], v[3], v[6])
            pz.append({"lado": "East" if "East" in m.group(2) else "West",
                       "a": tuple(o[i] - x[i] for i in range(3)),
                       "b": tuple(o[i] + x[i] for i in range(3)),
                       "span": (m.start(), m.end())})
        uf = list(range(len(pz)))

        def raiz(i):
            while uf[i] != i:
                uf[i] = uf[uf[i]]
                i = uf[i]
            return i

        for i in range(len(pz)):
            for j in range(i + 1, len(pz)):
                if min(math.dist(e1, e2) for e1 in (pz[i]["a"], pz[i]["b"])
                       for e2 in (pz[j]["a"], pz[j]["b"])) < 0.35:
                    ri, rj = raiz(i), raiz(j)
                    if ri != rj:
                        uf[ri] = rj
        grupos = {}
        for i in range(len(pz)):
            grupos.setdefault((pz[i]["lado"], raiz(i)), []).append(i)
        fuera = []
        for lado in ("West", "East"):
            propios = {k: v for k, v in grupos.items() if k[0] == lado}
            if len(propios) <= 1:
                continue
            mayor = max(propios.values(), key=len)
            for v in propios.values():
                if v is not mayor:
                    fuera += v
        if not fuera:
            break
        islas += len(fuera)
        for ini, fin in sorted((pz[i]["span"] for i in fuera), reverse=True):
            texto = texto[:ini] + texto[fin:]

    print("piezas podadas por quedar aisladas: %d" % islas)

    # Reenganche de valvulas, DESPUES de podar: si se hace antes, una valvula
    # puede quedar pegada a una pieza que la poda despues se lleva. Al sacarlas quedan flotando, asi que se las
    # reengancha a la punta de caño mas cercana de SU piso y SU mitad: misma valvula,
    # mismo piso, mismo circuito — solo se corre unos grados sobre el mismo anillo.
    movidas = []
    ext = extremos(texto)

    def _mover(m):
        nombre, lado = m.group(1), ("East" if m.group(2) == "East" else "West")
        piso = int(m.group(3))
        v = [float(x) for x in m.group(4).split(",")]
        if piso == 0 or (piso, lado) not in ext:
            return m.group(0)
        ang = math.degrees(math.atan2(v[11], v[9])) % 360.0
        if lado == "East" and ang > 180.0:
            ang -= 360.0
        destino = min(ext[(piso, lado)], key=lambda a: abs(a - ang))
        d = math.radians(destino - ang)
        c, s = math.cos(d), math.sin(d)
        # rotacion de la base entera alrededor de Y: la valvula sigue mirando radial
        b = [[v[0], v[1], v[2]], [v[3], v[4], v[5]], [v[6], v[7], v[8]]]
        rot = [[c * b[0][k] + s * b[2][k] for k in range(3)],
               b[1],
               [-s * b[0][k] + c * b[2][k] for k in range(3)]]
        o = ext[(piso, lado)][destino]
        movidas.append((nombre, ang, destino))
        return (m.group(0).split("transform =")[0] + "transform = Transform( "
                + ", ".join("%g" % x for x in
                            rot[0] + rot[1] + rot[2] + [o[0], v[10], o[2]]) + " )\n")

    texto = re.sub(r'^\[node name="(Valve(West|East)Floor(\d))"[^\n]*\]\n'
                   r'transform = Transform\(([^)]*)\)\n', _mover, texto, flags=re.M)


    print("vueltas de la S generadas:")
    for lado, n, giro, abajo, arriba in nuevos:
        print("  %-5s Floor_%d -> Floor_%d  en %6.1f deg  (y %.2f -> %.2f)" % (
            lado, n, n + 1, giro, abajo[1], arriba[1]))
    print("\nvalvulas reenganchadas: %d" % len(movidas))
    for n, a, d in movidas:
        print("   %-18s %6.1f -> %6.1f deg" % (n, a, d))
    print("\nT reemplazadas: %d" % quitadas)
    for r in rotos:
        print("CADENA PARTIDA: %s" % r)
    if dry:
        print("(dry-run: no escribi nada)")
        return
    PIPES.write_text(texto)
    print("escrito %s" % PIPES.name)


if __name__ == "__main__":
    main()
