#!/usr/bin/env python3
"""Peso muerto del pck: que se empaqueta y no lo alcanza ninguna escena viva.

El `include_filter` de los presets barre con globs anchos (`core_v2/**/*.tscn`,
`assets/**/*.png`, ...) que NO caminan dependencias, asi que meten al pck mucho
mas que lo alcanzable desde el arranque. Este script cruza las dos cosas y dice
cuanto sobra y donde.

    scripts/audit_pck_deadweight.py <index.pck>

El .pck se saca con:
    tools/godot --path . --no-window --export-pack "HTML5 Threads" /tmp/x.pck

Ojo al leer rutas: las hay con espacios ("Fabric Leather 02"), asi que el string
se lee ENTERO entre comillas. Cortar en el espacio marca como muerto lo que esta
vivo -- es el error que hay que no repetir al tocar esto.
"""
import collections
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUOTED = re.compile(r'["\'](res://[^"\']+)["\']')
BARE = re.compile(r'res://[^"\'\)\s\],]+')
TEXTY = {".tscn", ".tres", ".gd", ".material", ".godot", ".cfg", ".shader", ".escn"}

# Desde donde arranca el juego. Al reconectar un nivel, agregarlo aca.
RAICES = [
    "res://project.godot",
    "res://core_v2/bootstrap/Boot.tscn",
    "res://core_v2/ui/Menu.tscn",
    "res://core_v2/levels/RingHub_Level.tscn",
]


def _disk(res_path):
    return os.path.join(ROOT, res_path[len("res://"):])


def _refs(res_path):
    f = _disk(res_path)
    if os.path.splitext(f)[1].lower() not in TEXTY or not os.path.isfile(f):
        return []
    txt = open(f, encoding="utf-8", errors="ignore").read()
    return QUOTED.findall(txt) + [r.rstrip(".,") for r in BARE.findall(txt)]


def cierre_vivo():
    gd = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    raices = set(RAICES)
    if "[autoload]" in gd:
        raices |= set(re.findall(r'res://[^"]+', gd.split("[autoload]")[1].split("\n[")[0]))
    visto, cola = set(), collections.deque(raices)
    while cola:
        p = cola.popleft()
        if p in visto:
            continue
        visto.add(p)
        for r in _refs(p):
            if r not in visto and os.path.exists(_disk(r)):
                cola.append(r)
    return visto


def artefactos_a_fuente():
    """res://.import/foo-<hash>.stex -> res://assets/foo.png"""
    out = {}
    for dp, _, fns in os.walk(ROOT):
        if "/.kilo" in dp or "/.git" in dp:
            continue
        for x in fns:
            if not x.endswith(".import"):
                continue
            txt = open(os.path.join(dp, x), encoding="utf-8", errors="ignore").read()
            src = "res://" + os.path.relpath(os.path.join(dp, x[:-7]), ROOT).replace(os.sep, "/")
            for a in re.findall(r'res://\.import/[^"\']+', txt):
                out[a] = src
    return out


def listar_pck(path):
    f = open(path, "rb")
    if f.read(4) != b"GDPC":
        raise SystemExit("no parece un .pck de Godot: " + path)
    struct.unpack("<4I", f.read(16))
    f.read(64)
    n, = struct.unpack("<I", f.read(4))
    out = []
    for _ in range(n):
        pl, = struct.unpack("<I", f.read(4))
        p = f.read(pl).rstrip(b"\x00").decode("utf-8", "replace")
        _off, size = struct.unpack("<QQ", f.read(16))
        f.read(16)
        out.append((p, size))
    return out


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    vivo, a2s = cierre_vivo(), artefactos_a_fuente()
    peso = collections.Counter()
    for p, size in listar_pck(sys.argv[1]):
        peso[a2s.get(p, p)] += size
    total = sum(peso.values())
    dentro = sum(s for k, s in peso.items() if k in vivo)
    print("pck total        %8.1f MB" % (total / 1e6))
    print("cierre vivo      %8.1f MB  (%.0f%%)" % (dentro / 1e6, 100.0 * dentro / total))
    print("peso muerto      %8.1f MB  (%.0f%%)\n" % ((total - dentro) / 1e6,
                                                     100.0 * (total - dentro) / total))
    carpetas = collections.defaultdict(lambda: [0, 0])
    for k, s in peso.items():
        if not k.startswith("res://"):
            continue
        d = os.path.dirname(k[len("res://"):])
        carpetas[d][0] += s
        if k in vivo:
            carpetas[d][1] += s
    muertas = [(d, t) for d, (t, lv) in carpetas.items() if lv == 0 and t > 300_000]
    muertas.sort(key=lambda x: -x[1])
    print("carpetas sin un solo archivo vivo (candidatas a exclude_filter):")
    for d, t in muertas[:30]:
        print("  %8.1f MB  %s/*" % (t / 1e6, d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
