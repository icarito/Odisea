#!/usr/bin/env python3
"""Arma el circuito de coolant de Dome_Intro sobre la fuente ya migrada a rutas.

Corre DESPUES de fit_pipes_to_criopods.py, generate_pipe_serpentine.py y
migrate_pipes_to_routes.py. Todo lo que hace es idempotente y esta aca —y no en una
edicion suelta— porque la fuente se reconstruye desde HEAD cada vez que hay que
rehacer algo: parchar el .tscn a mano acumulo residuos (nodos sin puntos, piezas de
construcciones viejas) que costaron varias rondas de diagnostico.

  1. nodos Turns/ para las vueltas de la serpentina (el baker recorre recursivo:
     si cuelgan del tronco se traga los grupos por piso)
  2. el cruce oeste-este del piso 5 (Interlink), que el esquematico dibuja
  3. apply_flow_material=false en cada run: el kit ya trae su PBR
  4. la valvula del kit en vez de la vieja
  5. hueco en cada vertical para que la valvula no quede embebida en el cano

Uso: python3 tools/assemble_dome_intro_coolant.py
"""

import math
import pathlib
import re

RAIZ = pathlib.Path(__file__).resolve().parent.parent
INT = RAIZ / "core_v2/levels/interiors"
FUENTE = INT / "DomeIntro_PipeNetworkSource.tscn"
DOME = INT / "Dome_Intro.tscn"
# La valvula del kit escalada x4 (mismo factor que PipeRoute.grosor) ocupa 1.6 m
# desde su pivote, que esta en la BASE de la pieza.
LARGO_VALVULA = 1.6
HOLGURA = 0.05
PISOS = {1: (0.0, 4.08), 2: (4.08, 8.58), 3: (8.58, 13.08),
         4: (13.08, 17.58), 5: (17.58, 22.08)}


def main():
    t = FUENTE.read_text()
    t_local = [None]
    rid = int(re.search(r'kit/PipeRoute\.gd"[^\]]*id=(\d+)\]', t).group(1))
    run_id = int(re.search(r'PipeCoolantRun\.gd"[^\]]*id=(\d+)\]', t).group(1))

    def pts(grupo):
        m = re.search(r'^\[node name="Route" type="Spatial" parent="%s"\]\n'
                      r'script = ExtResource\( \d+ \)\n'
                      r'puntos = PoolVector3Array\(([^)]*)\)' % re.escape(grupo), t, re.M)
        v = [float(x) for x in m.group(1).split(",")]
        return [(v[i], v[i + 1], v[i + 2]) for i in range(0, len(v), 3)]

    # 1. las vueltas van a un nodo propio; el padre se declara ANTES que el hijo
    for lado in ("TowerCoolantRiser", "TowerCoolantRiserEast"):
        anc = '[node name="Route" type="Spatial" parent="%s"]' % lado
        if anc in t:
            decl = ('[node name="Turns" type="Spatial" parent="%s"]\n'
                    'script = ExtResource( %d )\napply_flow_material = false\n\n' % (lado, run_id))
            t = t.replace(anc, decl + anc.replace('parent="%s"' % lado,
                                                  'parent="%s/Turns"' % lado), 1)

    # 2. cruce oeste-este en el piso 5
    w = pts("TowerCoolantRiser/TowerCoolantRiser_L5_Ring")[-1]
    e = pts("TowerCoolantRiserEast/TowerCoolantRiserEast_L5_Ring")[0]
    r = math.hypot(w[0], w[2])
    medio = (math.cos(math.radians(270)) * r, w[1], math.sin(math.radians(270)) * r)
    t = t.rstrip("\n") + (
        '\n\n[node name="Interlink" type="Spatial" parent="TowerCoolantRiser"]\n'
        'script = ExtResource( %d )\napply_flow_material = false\n\n'
        '[node name="Route" type="Spatial" parent="TowerCoolantRiser/Interlink"]\n'
        'script = ExtResource( %d )\npuntos = PoolVector3Array( %s )\n'
        % (run_id, rid, ", ".join("%g" % c for q in (w, medio, e) for c in q)))

    # 3. PBR del kit
    t = re.sub(r'^(script = ExtResource\( %d \))\n(?!apply_flow_material)' % run_id,
               r'\1\napply_flow_material = false\n', t, flags=re.M)

    # 4. valvula del kit
    t = t.replace('res://core_v2/props/pipe/PipeValve.tscn',
                  'res://core_v2/props/pipe/kit/PipeValveKit.tscn')

    # 4b. Verticales que la migracion no puede recuperar: sus piezas originales ya
    # no existen en HEAD (las consumieron fit/serpentina), asi que el grupo queda sin
    # ruta y su malla horneada nunca se regenera — Dome_Intro se queda mostrando la
    # vieja. Se sintetizan con la misma convencion que los que si sobreviven.
    t_local[0] = t
    faltantes = []
    for lado, ang in (("TowerCoolantRiser", 180.0), ("TowerCoolantRiserEast", 0.0)):
        for piso in range(1, 6):
            grupo = "%s/%s_L%d" % (lado, lado, piso)
            if re.search(r'^\[node name="Route" type="Spatial" parent="%s"\]' % re.escape(grupo),
                         t_local[0], re.M):
                continue
            lo, hi = PISOS[piso]
            a = math.radians(ang)
            x, z = math.cos(a) * 12.0, math.sin(a) * 12.0
            t_local[0] = t_local[0].rstrip("\n") + (
                '\n\n[node name="Route" type="Spatial" parent="%s"]\n'
                'script = ExtResource( %d )\n'
                'puntos = PoolVector3Array( %g, %g, %g, %g, %g, %g )\n'
                % (grupo, rid, x, lo, z, x, hi, z))
            faltantes.append(grupo.split("/")[-1])

    t = t_local[0]

    # 5. hueco para la valvula. Las alturas mandan desde Dome_Intro: la fuente y la
    # escena de juego discrepaban y la de juego es la que ve el jugador.
    alturas = {}
    for m in re.finditer(r'^\[node name="Valve(West|East)Floor(\d)"[^\n]*\]\n'
                         r'transform = Transform\(([^)]*)\)', DOME.read_text(), re.M):
        alturas[(m.group(1), int(m.group(2)))] = float(m.group(3).split(",")[10])

    huecos = []

    def parte(m):
        grupo, piso, sc = m.group(1), int(m.group(2)), m.group(3)
        v = [float(x) for x in m.group(4).split(",")]
        lado = "East" if "East" in grupo else "West"
        lo, hi = PISOS[piso]
        y = alturas.get((lado, piso - 1))
        if y is None:
            return m.group(0)
        a, b = y - HOLGURA, y + LARGO_VALVULA + HOLGURA
        if not (lo < a and b < hi):
            return m.group(0)
        huecos.append("%s %.2f-%.2f" % (grupo.split("/")[-1], a, b))
        return ('[node name="Route" type="Spatial" parent="%s"]\nscript = ExtResource( %s )\n'
                'puntos = PoolVector3Array( %g, %g, %g, %g, %g, %g )\n\n'
                '[node name="Route2" type="Spatial" parent="%s"]\nscript = ExtResource( %s )\n'
                'puntos = PoolVector3Array( %g, %g, %g, %g, %g, %g )\n'
                % (grupo, sc, v[0], lo, v[2], v[0], a, v[2],
                   grupo, sc, v[0], b, v[2], v[0], hi, v[2]))

    t = re.sub(r'\[node name="Route" type="Spatial" parent="([^"]*_L(\d))"\]\n'
               r'script = ExtResource\( (\d+) \)\n'
               r'puntos = PoolVector3Array\(([^)]*)\)\n', parte, t)

    FUENTE.write_text(t)
    malas = [l for l in t.splitlines() if l and not l.startswith("[") and "=" not in l]
    print("runs en PBR: %d | verticales sintetizados: %s | huecos de valvula: %d | corruptas: %d"
          % (t.count("apply_flow_material = false"), faltantes or "-", len(huecos), len(malas)))
    for h in huecos:
        print("   " + h)


if __name__ == "__main__":
    main()
