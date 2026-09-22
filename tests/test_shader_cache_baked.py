"""Las escenas de warmup deben venir horneadas (tools/bake_shader_cache.gd).

Sin hornear, ShaderCache.cache_scene() corre en runtime: instancia el nivel
entero en un SceneTree virtual y le corre _ready() a todo. Medido en desktop
nativo: 1.1 s (RingHub) y 3.0 s (Dome_Intro) de UN frame bloqueado, que en
HTML5 es el cuelgue del navegador despues de "[ShaderCacheManager] compiling:".
"""
import pathlib

import pytest

# Solo los caches que el build carga hoy. Hornear el de un nivel inalcanzable lo
# vuelve dependencia real del export (peso muerto en el pck), asi que el resto
# queda a proposito sin hornear. Ver tools/bake_shader_cache.gd.
EN_USO = ["RingHubShaderCache.tscn"]
CACHES = [pathlib.Path(__file__).resolve().parents[1] /
          "core_v2" / "levels" / "shader_cache" / n for n in EN_USO]


def test_hay_escenas_de_cache():
    assert CACHES and all(c.exists() for c in CACHES)


@pytest.mark.parametrize("scene", CACHES, ids=lambda p: p.name)
def test_cache_horneado(scene):
    text = scene.read_text(encoding="utf-8")
    assert 'name="Materials"' in text or 'name="ParticlesMaterials"' in text, (
        "%s no tiene quads horneadas; volver a correr "
        "tools/godot --path . -s tools/bake_shader_cache.gd" % scene.name)
