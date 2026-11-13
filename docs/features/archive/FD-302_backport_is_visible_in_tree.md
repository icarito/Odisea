# FD-302 — Backport GH-107324: `is_visible_in_tree` pre-calculado al pin 3.6.4-rc

- **Status:** Planned
- **Priority:** Medium
- **Effort:** Medium (adaptación manual a 3.6, no cherry-pick limpio)
- **Created:** 2026-09-17
- **Repo de entrega:** `icarito/Odisea` (esta rama)
- **Repo destino final:** `icarito/godot-box3d-3` (solo referencia; la copia a `patches/` del fork es manual, post-merge, por Sebastián/Odiseo)

## Contexto

El fork `icarito/godot-box3d-3` pinea Godot `3.6.4-rc`
(`GODOT_REF=6371881f6742425cc14eaa367f18dd95955bf5e5`) y aplica sus patches
desde `patches/*.patch` en orden alfabético vía `scripts/build.sh`.

En Godot 3.x, `Spatial::is_visible_in_tree()` camina el árbol hacia arriba en
CADA llamada — O(profundidad) por consulta. El PR upstream GH-107324
(`godotengine/godot@67265bacd54577a57f7dc376ca7bc878e0c8c27c`) pre-calcula el
estado en `data.visible_in_tree` y lo propaga en enter/exit tree, show/hide y
reparent. Odisea consulta visibilidad en rutas calientes de core_v2
(partículas de gas, cinematografía, LOD), así que el cambio vale la pena.

**De los 3 backports evaluados, 2 YA están en el pin 3.6.4-rc** (verificado
contra los fuentes del pin, no asumir):

| PR upstream | Estado en pin | Evidencia |
|---|---|---|
| GH-106021 (Xbox en Android) | ✅ YA ESTÁ | `KEYCODE_BUTTON_MODE`/`KEYCODE_MEDIA_RECORD` en `GodotInputHandler.java`; las 3 líneas de Xbox en `main/godotcontrollerdb.txt` |
| GH-97464 (cleanup conexiones GDScript) | ✅ YA ESTÁ | guard `ObjectDB::get_instance(state_id)` + `_clear_stack()` en `gdscript.cpp:88-90` y `1382-1384` |
| GH-107324 (precalc `is_visible_in_tree`) | ❌ FALTA | el pin aún camina el árbol: `scene/3d/spatial.cpp:748` |

Por tanto esta FD cubre SOLO GH-107324.

## Tarea

Adaptar el patch upstream de GH-107324 (commit master
`67265bacd54577a57f7dc376ca7bc878e0c8c27c`; snapshot exacto incluido en
`docs/features/FD-302_assets/upstream_master_67265ba.patch`) a los internos de
3.6.4-rc y entregar el resultado como:

```
patches/upstream_is_visible_in_tree_precalc.patch
```

en ESTA rama de Odisea.

### Diferencias 3.6 vs master a resolver

- Los hunks upstream (7 en `spatial.cpp`, 3 en `spatial.h`) tocan
  `_notification`, `show()`, `hide()`, constructor y el struct `data` de
  `spatial.h`. Las líneas NO calzan 1:1 con 3.6: re-anclar cada hunk contra el
  árbol del pin.
- 3.6 tiene `_propagate_transform_changed` con `data.children_lock` (master
  también, pero con estructura distinta). La propagación de visibilidad nueva
  NO debe colisionar con ese gate ni heredarlo incorrectamente.
- Preservar la semántica upstream: `data.visible_in_tree` cacheado,
  `_update_visible_in_tree()` y `_propagate_visible_in_tree(bool)`.

## Restricciones

- NO tocar `scripts/build.sh` ni el sistema de patches del fork (solo entregar
  el archivo `.patch`; el README del fork se actualiza a mano después).
- NO tocar condicionales GLES3 (`USE_BLOB_SHADOWS`, bit 8 del budget, etc.).
- Nombre de archivo plano (fix upstreamable), NO prefijo `zzz_*`.
- NO intentar compilar Godot ni disparar CI: la verificación de build corre
  después, en el fork.

## Verificación (obligatoria)

1. Reconstruir el árbol del pin y verificar que el patch aplica limpio:
   ```bash
   PIN=6371881f6742425cc14eaa367f18dd95955bf5e5
   rm -rf /tmp/pin && mkdir /tmp/pin && cd /tmp/pin && git init -q .
   for f in scene/3d/spatial.cpp scene/3d/spatial.h; do
     mkdir -p "$(dirname "$f")"
     curl -s "https://raw.githubusercontent.com/godotengine/godot/$PIN/$f" -o "$f"
   done
   git add -A && git -c user.email=a@b -c user.name=a commit -qm pin
   git apply --check /ruta/al/patches/upstream_is_visible_in_tree_precalc.patch && echo OK
   ```
2. `git apply --check` debe salir sin errores (los desplazamientos de línea
   son esperables; los conflictos de contexto no).
3. Auto-revisión: cada hunk del patch original debe tener equivalente en el
   adaptado (mismo propósito, anclas ajustadas a 3.6).

## Entregable

- `patches/upstream_is_visible_in_tree_precalc.patch` (adaptado al pin)
- En la descripción del PR: la fila sugerida para la tabla
  `patches/README.md` del fork (formato `Patch | Bug/motivo | Detalle`, bilingüe).
