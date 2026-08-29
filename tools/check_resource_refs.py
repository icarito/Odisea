#!/usr/bin/env python3
"""Verifica que toda ruta res:// de los .tscn/.tres del repo apunte a un archivo real.

Existe porque renombrar o mover un asset rompe en silencio a quien lo referencia: la
escena deja de cargar y solo te enteras cuando un test lejano falla con un mensaje que
no menciona el archivo. Paso exactamente eso al pasar
`textures/prototype_textures/purple 2.png` a `purple_2.png`: se llevo puesto
`TestScene_v2.tscn` y con el los 12 tests de determinismo.

    python3 tools/check_resource_refs.py

Sale 1 si aparece una referencia colgada nueva.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH_RE = re.compile(r'path="(res://[^"]+)"')
EXTS = (".tscn", ".tres", ".import")

# Artefactos de build, cache y salidas: no son fuente.
SKIP_DIRS = {"android", "build", ".import", "ports", ".git", "reports",
             "test_output", "node_modules", ".venv", "dashboard"}

# Referencias colgadas que YA estaban antes de este chequeo. Son demos de la
# asset library que se copiaron a medias y un .glb que nunca entro al repo. Se
# listan para que el chequeo pueda fallar limpio ante una rotura NUEVA.
KNOWN_DANGLING = {
    "assets/FX/Volumetric_Lights/scene.tscn",
    "assets/FX/particle_system_effects_Godot3/scene.tscn",
    "assets/FX/particle_system_effects_Godot3/default_env.tres",
    "scenes/common/Odisea.tscn",
}


def main():
    os.chdir(REPO)
    new_bad = {}
    known_hits = 0

    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if not name.endswith(EXTS):
                continue
            path = os.path.normpath(os.path.join(root, name))
            # Un .import de maps/autosave apunta a cache que puede no existir.
            if os.sep + "autosave" + os.sep in path:
                continue
            try:
                text = open(path, errors="replace").read()
            except OSError:
                continue
            missing = sorted({r for r in PATH_RE.findall(text)
                              if not os.path.exists(r[len("res://"):])})
            if not missing:
                continue
            if path.replace(os.sep, "/").lstrip("./") in KNOWN_DANGLING:
                known_hits += len(missing)
                continue
            # Un .import referencia su propio artefacto en .import/, que se regenera.
            if path.endswith(".import") and all(m.startswith("res://.import/") for m in missing):
                continue
            new_bad[path] = missing

    for path, missing in sorted(new_bad.items()):
        print("ROTA %s" % path)
        for m in missing:
            print("       -> %s" % m)

    if new_bad:
        print("\n%d archivo(s) con referencias colgadas nuevas" % len(new_bad))
        return 1
    print("check_resource_refs: OK (%d colgadas conocidas y toleradas)" % known_hits)
    return 0


if __name__ == "__main__":
    sys.exit(main())
