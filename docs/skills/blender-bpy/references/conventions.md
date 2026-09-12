# Convenciones de assets 3D — Odisea (Godot 3.6)

## Entorno del host (Odiseo)

- Blender **4.3.2** (build Debian, `apt install blender`).
- Python embebido = Python del sistema (`/usr/bin/python3.13`), con `python3-numpy`.
- **Sin GPU** (no `/dev/dri`): render por CPU. EEVEE Next funciona en software; el
  error `EGL_BAD_MATCH` en stderr es inofensivo.
- Motor de render: `BLENDER_EEVEE_NEXT` (el enum `BLENDER_EEVEE` de 3.x ya no existe en 4.3).

## Target de import

- **Godot 3.6 / GDScript 1.x** (fork Box3D vía `tools/godot`). Nunca Godot 4.
- Formato: **`.glb`** (glTF binary), ubicado en `assets/models/<Nombre>/`.
- Coordenadas Godot no estándar: **`+Z = BACK`, `-Z = FORWARD`**. Tras importar, validar
  la orientación del modelo (cámara por detrás del personaje mirando a -Z).

## Escala

- Trabajar en **metros** como unidad de Blender (1 bu = 1 m). Blender por defecto ya usa metros.
- Mantener props a escala humana coherente con los `.glb` existentes en `assets/models/`.
- Al exportar, usar `export_apply=True` (aplicar transforms) para no arrastrar escalas raras.

## Paleta de materiales (fuente: docs/agents/tooling.md)

| Nombre | Metallic | Roughness | Albedo | Emission |
|---|---|---|---|---|
| Brushed steel claro | 1.0 | 0.18 | (0.42, 0.44, 0.46) | — |
| Brushed steel oscuro | 1.0 | 0.30 | (0.30, 0.32, 0.34) | — |
| Interactable cyan | 0.0 | 0.3 | (0.15, 0.80, 0.78) | (0, 0.55, 0.52) |
| Advertencia amarilla | 0.0 | 0.6 | (0.85, 0.68, 0.08) | — |

Helpers Python en `scripts/odisea_lib.py`.

## Naming

- Objetos con prefijo de tipo: `M_` materiales, meshes sin prefijo rígido, pero coherentes.
- Nombre de carpeta del modelo = nombre limpio en PascalCase (`IndustrialLever`, no `lever_final_2`).

## Pipeline de props (autoría → horneado)

Para props que viven en `core_v2/props/`, el `.glb` es **fuente**, no runtime directo:
autoría (`*Source.tscn`) → baker determinista (`tools/bake_*.gd`) → producto
(`.mesh`/`.shape`/`.material`). Ver `docs/agents/dome_source_mapping.md`.

Para props interactuables/decorativos de `core_v2/props/`, usar el flujo
`prop-visualizer` (`/odisea-prop`) con `test_prop.sh`.

## Gotchas Blender 4.3 + Godot 3

- glTF export de Blender 4.3 usa el nuevo pipeline; validar que Godot 3.6 (importer glTF 2)
  lo lea sin warning de versión. Si falla, re-exportar con `export_format="GLTF_SEPARATE"` y
  probar `.gltf`+`.bin`.
- Materiales metálicos muy pulidos (`metallic=1, roughness<0.25`) se ven **negros** en
  PropStage sin luz real. En juego con luz se ven bien; no compensar bajando metallic.
- `export_apply=True` fija los transforms al mesh; si el asset necesita jerarquía animada
  (armature), NO aplicar transforms al rig — exportar con `export_apply=False` y
  `export_animations=True`.
