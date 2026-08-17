#!/usr/bin/env python3
"""Mete el horneado de criopods dentro de Dome_Intro.tscn.

tools/bake_dome_intro_criopods.gd genera las mallas y deja un fragmento de nodos
(DomeIntro_Criopods.nodes) pero NO toca la escena: escribir un .tscn desde un
PackedScene.pack() de una instancia viva se lleva puesto el estado de runtime
(los Batched_* de RadialScatter, los materiales ya convertidos por
PropDitherManager, lo que haya streameado). Este script hace el reemplazo textual,
que es revisable en un diff.

Que hace:
  1. da de alta un ext_resource por cada malla horneada y por la forma compartida
  2. cambia los seis nodos Criopods* (RadialScatter + 218 pods instanciados) por los
     nodos horneados del fragmento
  3. borra los recursos que quedaron huerfanos (el script RadialScatter, la escena
     CriopodParallax, la malla y el material del pod embebidos en la escena), en
     iteracion hasta punto fijo porque un sub_resource borrado puede dejar huerfanas
     las texturas que referenciaba
  4. recalcula load_steps

Uso: python3 tools/splice_criopod_bake.py [--dry-run]
"""

import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ESCENA = RAIZ / "core_v2/levels/interiors/Dome_Intro.tscn"
FRAGMENTO = RAIZ / "core_v2/levels/interiors/DomeIntro_Criopods.nodes"

TIPO_POR_EXTENSION = {".mesh": "ArrayMesh", ".shape": "Shape", ".material": "Material"}


def leer_fragmento():
    """Devuelve (rutas_por_indice, lineas_de_nodos)."""
    rutas = {}
    cuerpo = []
    en_cabecera = True
    for linea in FRAGMENTO.read_text().splitlines():
        if en_cabecera:
            if linea == "#endext":
                en_cabecera = False
                continue
            m = re.match(r"#ext (\d+) (.+)$", linea)
            if not m:
                raise SystemExit("cabecera del fragmento ilegible: %r" % linea)
            rutas[int(m.group(1))] = m.group(2)
            continue
        cuerpo.append(linea)
    return rutas, cuerpo


def partir_en_bloques(lineas):
    """[(clase, id_o_None, [lineas])] — clase es 'header'/'ext'/'sub'/'node'/'otro'."""
    bloques = []
    actual = None
    for linea in lineas:
        if linea.startswith("["):
            clase, ident = "otro", None
            if linea.startswith("[gd_scene"):
                clase = "header"
            elif linea.startswith("[ext_resource"):
                clase = "ext"
            elif linea.startswith("[sub_resource"):
                clase = "sub"
            elif linea.startswith("[node"):
                clase = "node"
            if clase in ("ext", "sub"):
                m = re.search(r"\bid=(\d+)", linea)
                ident = int(m.group(1)) if m else None
            actual = (clase, ident, [linea])
            bloques.append(actual)
        elif actual is None:
            actual = ("otro", None, [linea])
            bloques.append(actual)
        else:
            actual[2].append(linea)
    return bloques


def referencias(bloques, clase_omitida_id):
    """Ids de ExtResource/SubResource usados por alguien. La linea de definicion de un
    recurso no cuenta como uso de si mismo, pero su CUERPO si (un material referencia
    sus texturas)."""
    usados = {"ext": set(), "sub": set()}
    for clase, ident, lineas in bloques:
        for i, linea in enumerate(lineas):
            if i == 0 and clase in ("ext", "sub"):
                continue  # la cabecera del propio recurso
            for m in re.finditer(r"ExtResource\(\s*(\d+)\s*\)", linea):
                usados["ext"].add(int(m.group(1)))
            for m in re.finditer(r"SubResource\(\s*(\d+)\s*\)", linea):
                usados["sub"].add(int(m.group(1)))
    return usados


def main():
    dry = "--dry-run" in sys.argv
    rutas, cuerpo_fragmento = leer_fragmento()
    lineas = ESCENA.read_text().splitlines()
    bloques = partir_en_bloques(lineas)

    # --- 1. ids nuevos para las mallas horneadas -------------------------------
    ids_ext = [b[1] for b in bloques if b[0] == "ext" and b[1] is not None]
    siguiente = max(ids_ext) + 1
    # Re-aplicar un bake no debe duplicar 19 ext_resources identicos solo porque
    # la escena ya apunta a los productos de una corrida anterior. Reusar por
    # ruta mantiene el .tscn estable y evita churn textual innecesario.
    ext_existente_por_ruta = {}
    for clase, ident, ls in bloques:
        if clase != "ext" or ident is None:
            continue
        m = re.search(r'\bpath="([^"]+)"', ls[0])
        if m:
            ext_existente_por_ruta[m.group(1)] = ident
    id_real = {}
    nuevos_ext = []
    for indice in sorted(rutas):
        ruta = rutas[indice]
        if ruta in ext_existente_por_ruta:
            id_real[indice] = ext_existente_por_ruta[ruta]
            continue
        tipo = TIPO_POR_EXTENSION[Path(ruta).suffix]
        id_real[indice] = siguiente
        nuevos_ext.append(
            '[ext_resource path="%s" type="%s" id=%d]' % (ruta, tipo, siguiente)
        )
        siguiente += 1

    cuerpo = []
    for linea in cuerpo_fragmento:
        cuerpo.append(
            re.sub(
                r"ExtResource\(\s*(\d+)\s*\)",
                lambda m: "ExtResource( %d )" % id_real[int(m.group(1))],
                linea,
            )
        )

    # --- 2. reemplazar los nodos Criopods* -------------------------------------
    # El rango a reemplazar es TODO nodo que cuelgue de un anillo: el header
    # "Criopods\d+", sus hijos directos (Item_N sin hornear, o Shell/Glass/
    # PersonCards/StaticBody ya horneados) y los nietos (Pod_NN bajo el
    # StaticBody, o el StaticBody/CollisionShape que traía cada Item_N viejo).
    # Si esto solo mirara "Criopods\d+" + "Item_\d+" (como antes), un re-bake
    # sobre una escena YA horneada no encuentra ningun Item_N -> ultimo se
    # queda en el header y los hijos horneados de Criopods6 (los ultimos del
    # archivo) quedan afuera del rango, huerfanos sin borrar.
    primero = ultimo = None
    for i, (clase, _ident, ls) in enumerate(bloques):
        if clase != "node":
            continue
        if re.match(r'\[node name="Criopods\d+" ', ls[0]) or re.search(
            r'\bparent="Spatial/Criopods\d+(/|")', ls[0]
        ):
            primero = i if primero is None else primero
            ultimo = i
    if primero is None:
        raise SystemExit("no encontre los nodos Criopods* — ¿ya esta horneado?")
    viejos = ultimo - primero + 1
    bloques[primero : ultimo + 1] = [("node", None, cuerpo)]

    # --- 3. dar de alta los ext_resource nuevos --------------------------------
    ultimo_ext = max(i for i, b in enumerate(bloques) if b[0] == "ext")
    bloques[ultimo_ext + 1 : ultimo_ext + 1] = [("ext", None, [l]) for l in nuevos_ext]

    # --- 4. barrer huerfanos hasta punto fijo ----------------------------------
    borrados = []
    while True:
        usados = referencias(bloques, None)
        sobrantes = [
            i
            for i, (clase, ident, _l) in enumerate(bloques)
            if clase in ("ext", "sub") and ident is not None and ident not in usados[clase]
        ]
        if not sobrantes:
            break
        for i in reversed(sobrantes):
            borrados.append(bloques[i][2][0])
            del bloques[i]

    # --- 5. load_steps ---------------------------------------------------------
    recursos = sum(1 for b in bloques if b[0] in ("ext", "sub"))
    for i, (clase, ident, ls) in enumerate(bloques):
        if clase == "header":
            bloques[i] = (
                clase,
                ident,
                [re.sub(r"load_steps=\d+", "load_steps=%d" % (recursos + 1), ls[0])],
            )
            break

    salida = "\n".join(l for _c, _i, ls in bloques for l in ls)
    if not salida.endswith("\n"):
        salida += "\n"

    print("nodos reemplazados: %d -> %d" % (viejos, len(cuerpo_fragmento) and 1))
    print("ext_resource nuevos: %d" % len(nuevos_ext))
    print("recursos huerfanos borrados: %d" % len(borrados))
    for l in borrados:
        print("   " + l)
    print("load_steps: %d" % (recursos + 1))
    print("tamano: %d -> %d bytes" % (ESCENA.stat().st_size, len(salida.encode())))

    if dry:
        print("(dry-run: no escribi nada)")
        return
    ESCENA.write_text(salida)


if __name__ == "__main__":
    main()
