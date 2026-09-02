# Renderer GLES3 en iOS — decisión, bug de meshes invisibles y estado

> Estado: **RESUELTO y confirmado en device** (build posterior a `27bea2aa`, 2026-09-02).
> Este documento es la fuente de verdad del renderer del proyecto. Lo creó el debugging
> asistido por agentes; cualquier cambio de renderer o de `shader_compilation_mode` debe
> actualizarlo.

## 1. Dónde está parado el proyecto

| Plataforma | Renderer | Override en `project.godot` | Shader compilation |
|---|---|---|---|
| Desktop (Linux/Win/macOS) | GLES3 (default del motor, sin override global) | — | `mode=2` (async + cache binaria) |
| iOS | GLES3 (estándar del motor) | `driver_name.iOS="GLES3"` | **`mode=0` (síncrono) — CONTRACTO** |
| Android | GLES3 con fallback automático a GLES2 | `fallback_to_gles2=true` | `mode.mobile=2` (riesgo, ver §6) |
| Web/HTML5 | GLES3 (WebGL2) | — | `mode.web=2` (riesgo conocido, ver §6) |

Nunca borrar `quality/driver/fallback_to_gles2=true`: es la red de seguridad si GLES3 no
inicializa en algún device.

## 2. Por qué se abandonó GLES2 en iOS

GLES2 en iOS expone **8 unidades de textura**. El driver del motor ata los samplers de
material desde la unidad 0 y los built-ins desde el tope (lightmap + screen_texture +
depth_texture **comparten** `max-4`), así que materiales con varios samplers colisionan
**silenciosamente** (sin error de linkeo). Medido en device: asignaciones `ok=39 fallos=0`,
log limpio, y el bake igual ausente. La pila de workarounds (IOSLightmapFallback, budget
de varyings, dither bayer manual) nunca resolvió los síntomas. Todo ese stack quedó
**obsoleto**: `IOSLightmapFallback.gd` es opt-in vía `ODISEA_MANUAL_LIGHTMAP=1` y nadie
mantiene paridad visual GLES2.

En GLES3 el bake aplicó sin tocar nada (build `559a0429`): lightmap nativo,
SpatialMaterial estándar, mismo PropDitherManager que desktop.

## 3. El bug: meshes invisibles en GLES3-iOS, log limpio

**Síntoma** (build nightly 500, commit `dff33286` "gles3!"): `Pilot_V2` invisible y
"varios mesh" sin verse en iOS. El floor, holo panels y pipes (`.mesh` ensamblados) se
veían bien. El LogOverlay no mostró **ningún** error de shader.

**Causa raíz**: `rendering/gles3/shaders/shader_compilation_mode=2` (async + cache).
Es un camino **exclusivo de GLES3** — GLES2 compila siempre síncrono, por eso nunca pudo
fallar así. Con async, cada variante se dibuja primero vía el **ubershader** (un
mega-shader precompilado al arranque que decide todo por branching runtime con el uniform
`ubershader_flags`). En `ShaderGLES3::_bind()` (`shader_gles3.cpp`), cuando el shader
específico aún no está listo y no hay ubershader utilizable, el motor hace
`unbind(); return false` → **el mesh se saltea sin loguear nada**. En el driver GL de
Apple, el camino async/ubershader falla silenciosamente: ni ubershader ni variantes, y
nada en el log.

**Descartado con evidencia**: la compresión octaédrica de los `.glb` (Pilot, Programmer,
Radiator, Misc_Heater, DomeFacade_01_LOD — todos `meshes/octahedral_compression=true`) NO
es la causa: GLES2 en el mismo device renderizó esos mismos meshes con el mismo import
(formato RGBA32F de textura de huesos incluido). El decode funciona en ese hardware; lo
que era GLES3-only era el sistema async/ubershader.

**Fix (confirmado en device)**: `shader_compilation_mode.iOS=0` — compilación síncrona.
El motor **bloquea** hasta tener el shader listo en vez de saltarse el mesh; si un shader
falla de verdad, el error aparece en el log. Commit `27bea2aa`.

## 4. Reglas operativas

- **No subir `shader_compilation_mode.iOS` a ≥1** sin un warmup de shaders por escena
  (compilar las variantes durante la pantalla de carga). Volver a async ahí reintroduce
  meshes invisibles sin diagnóstico.
- En `project.godot` la **última línea cuyo feature tag matchea gana**
  (`project_settings.cpp::_set` procesa en orden de archivo). Por eso `.iOS=0` va DESPUÉS
  de `.mobile`/`.web`. No reordenar esas líneas.
- Sonda de diagnóstico en device: Opciones → **Overlay de log** (lee
  `user://logs/godot.log`, filtra por ERROR/shader/GLES/failed). El boot siempre imprime
  `Async. shader compilation: ON (full native support) | ON (via secondary context) |
  OFF (...)` y `Shader cache: ON/OFF` — esa línea dice qué camino tomó el device. Si el
  overlay no muestra nada, desconfiar primero del overlay (file logging) y después del
  motor.
- Los meshes que vengan de `.glb` (ver Critical Imports en CI_Asset_Strategy.md) son los
  primeros afectados por cualquier regresión de este tipo; los `.mesh` ensamblados por
  scripts (`PipeValveKit_body.mesh`, criopods, baked) no pasan por import y sirven de
  grupo de control en screenshots.
- iOS siempre exporta en **release** (el template debug no archiva: "ARCHIVE FAILED").
  ANNAV2 bloquea comandos remotos en release → el diagnóstico en device es el overlay de
  log, no telemetría.

## 5. Evaluación GLES3: quedarse (recomendado inicial)

**Ventajas (ya verificadas en device):**
1. Un solo renderer estándar en todas las plataformas de juego = paridad visual real con
   desktop (glow HDR, lightmap, materiales). Se elimina una clase entera de bugs de
   divergencia.
2. Camino estándar del motor: lightmap nativo, SpatialMaterial, sin workarounds manuales
   que mantener. Menos superficie de bug, no más.
3. 16 unidades de textura en ES3 vs 8 en GLES2-iOS: las colisiones estructurales de
   sampler desaparecen.

**Costos aceptados:**
1. Compilación síncrona en iOS = hitchs al entrar por primera vez a una escena/zona (cada
   variante nueva bloquea 10–100 ms). Es el precio de ver los meshes; hasta que exista un
   warmup por escena (§6) no se recupera la fluidez perfecta en el primer paseo.
2. GLES2 queda como red de seguridad *parcialmente rota*: bootearía en devices viejos
   pero sin mantenimiento visual (IOSLightmapFallback opt-in, nadie ajusta el look).
   Asumido: Android moderno corre GLES3 (ES 3.0 = Android 4.3+, GPU ~2013+).

**Decisiones abiertas (no resueltas por este doc):**
- ¿Trackear `etc2.stex` en git? Ahora Android puede cargar GLES3 → las `.etc2.stex`
  empiezan a usarse. CI_Asset_Strategy.md §variantes ya quedó actualizado; validar tamaño
  del repo al activar el export Android.
- Web: `mode.web=2` tiene bug conocido de async en mobile browsers (godot#62450). Si el
  export HTML5 vuelve al alcance, evaluar `shader_compilation_mode.web=0`.
- Warmup de shaders por escena (compilar variantes durante la pantalla de carga) para
  poder re-evaluar async en iOS sin el riesgo de meshes invisibles.
- `PipeCoolantFresnel.tres` y el resto del tuning de emisión se hizo contra GLES3 HDR;
  GLES2 legacy no lo verá igual. Es aceptado, no un bug.

## 6. Si reaparece (checklist)

1. Confirmar el renderer en telemetría/overlay: `render_diag.video_driver == "GLES3"`.
2. Overlay de log: buscar `Async. shader compilation:` del boot. Si dice ON en iOS, alguien
   tocó `shader_compilation_mode.iOS` — volver a 0.
3. Si con mode 0 hay meshes invisibles **con** errores de shader en el log: es un shader
   del proyecto — leer el log completo (`user://logs/godot.log`) y arreglar el shader, no
   el renderer.
4. Si con mode 0 hay meshes invisibles **sin** errores: sospechar del vertex path GLES3
   (octaédrico o textura de huesos). Siguiente paso preparado: `meshes/octahedral_compression=false`
   + reimport en los 5 `.glb` (Pilot, Programmer, Radiator, Misc_Heater, DomeFacade_01_LOD).
   No tocar las dos cosas a la vez.
