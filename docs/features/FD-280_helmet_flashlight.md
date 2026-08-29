# FD-280: Linterna de casco — Spotlight con máscara holográfica

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-08-27
**Parent:** FD-250 (Dome_Intro bake) / Prologue (dome_prologue, pendiente de FD)

## Problem

El prologue abre a oscuras: Elías necesita iluminar la sala antes de encontrar el
interruptor de luz, y después vuelve a oscurecerse en el sótano. No existe ninguna
luz que el jugador lleve encima. Toda la iluminación del proyecto es estática (bake,
`LightPathV2`, props) o de proximidad; no hay luz "linterna" que siga la cámara.

Además, Sebastián quiere que la linterna sea **scifi y con carácter**: luz desde el
casco, y un efecto de "escaneo"/holograma. Pero debe ser **barata** — el proyecto es
GLES2 con límite de fillrate medido (ver `MobileLightBudget.gd`), así que no puede
meter otra luz dinámica cara ni postprocesado.

## Solution

Una **linterna de casco autónoma** montada en la cámara del piloto:

1. **SpotLight** hijo de la cámara (rango corto, sin sombras o sombras opcionales).
2. **Cono volumétrico con máscara** (fake beam) que reutiliza `volumetric_cone.shader`
   y le suma una textura de máscara scrolleable (scanlines/rejilla/glitch) para el
   efecto "escaneo holográfico".
3. Un parámetro de "modo escaneo" que alterna la máscara entre luz normal (solo cono)
   y pulso de escaneo (la máscara barre el cono), para vender el "escanea o hace algo
   holográfico" sin un sistema nuevo.

Todo es **una sola SpotLight + un mesh aditivo sin sombra**. No hay postprocesado, no
hay projector, no hay segunda pasada.

### Técnica de máscara en Godot 3

Godot 3 **no tiene cookie/gobo nativo** en `SpotLight` (el `light_mask` es para
culling, no es textura). Por eso la máscara se finta en el **cono volumétrico**:

- `core_v2/visual/volumetric_cone.shader` ya dibuja un cono aditivo (`blend_add,
  unshaded`) con falloff en `UV.y` y suavizado de borde en `UV.x`.
- Se extiende con `uniform sampler2D mask` + `uniform float mask_scroll` + `uniform
  vec2 mask_tiling`. En `fragment()` se muestrea la máscara y se multiplica el
  `ALPHA` (y opcionalmente el `ALBEDO`) para que el haz tenga la textura de scanline.
- El "escaneo" es el mismo `mask_scroll` animado: la textura barre a lo largo del cono.
  Barato: es un fetch de textura + una suma, sobre un mesh que ya existía.

### Considered Options

- **Projector real (MeshInstance quad con textura transparente delante de la luz)** —
  proyecta un patrón real sobre las superficies, pero agrega draw calls y una pasada
  transparente extra por frame; más caro y más frágil con el lightmap.
- **Shader de pantalla / postproceso de escaneo** — el efecto más bonito, pero rompe el
  presupuesto de GLES2 y no es "barato".
- **SpotLight sola (sin cono)** — lo más barato, pero no vende el "holograma/escaneo".
- **Selected:** SpotLight + cono volumétrico con máscara scrolleable. Reusa un shader
  existente, mantiene 1 luz dinámica, y el efecto se logra con un solo mesh aditivo.

## Contracts

- La linterna es **1 SpotLight + 1 MeshInstance (cono) + 1 ShaderMaterial**. Nada más.
- `shadow_enabled = false` por defecto; expuesto como flag para escritorio si el nivel
  lo pide, no para móvil.
- El cono usa `blend_add, unshaded` y **no** participa del bake (es runtime, como el
  resto del beam de `SearchLightV2`).
- Rango de la SpotLight **< 6.0 m** para que `MobileLightBudget` (`min_range_to_touch`)
  no la recorte: es la luz del casco y debe quedar intacta (ese autoload ya la excluye
  por rango, no hay que tocarlo).
- La linterna es **un nodo de escena autónomo**, no código acoplado al piloto: se
  instancia bajo la cámara (mismo patrón "attach to active camera" que
  `HelmetHUDV2.gd` / `hud_cfg_attach_to_active_camera`).
- Toggle por input (tecla de linterna); no depende del gloo ni del puzzle de coolant.

## Files to Modify

- `core_v2/visual/volumetric_cone.shader` (modify: sumar `mask`, `mask_scroll`,
  `mask_tiling`; retrocompatible si no se asigna textura).
- `core_v2/props/lights/HelmetFlashlight.gd` (new)
- `core_v2/props/lights/HelmetFlashlight.tscn` (new)
- `core_v2/props/lights/HelmetFlashlightMask.tres` (new, textura 512² o 1024² con
  scanlines/rejilla; usar VRAM + mipmaps como el resto)
- `core_v2/actors/Pilot_v2.tscn` (modify: instanciar `HelmetFlashlight` bajo
  `CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera`)
- `docs/features/FEATURE_INDEX.md` (modify)
- `docs/features/FD-280_helmet_flashlight.md` (new)

## Verification

1. F6 en `Dome_Intro` (o en la escena prologue cuando exista): la linterna se enciende
   y apaga por input, y el cono sigue la cámara sin lag ni offset visible.
2. Con la máscara activa, el haz muestra scanlines/rejilla y el "escaneo" barre sin
   tirones (animar `mask_scroll` en `_process`, no por físicas).
3. `MobileLightBudget` no recorta la linterna: su rango queda intacto en perfil móvil
   (por debajo de `min_range_to_touch`).
4. Presupuesto: la escena suma exactamente 1 luz dinámica y 1 mesh aditivo al abrir la
   linterna; apagarla los deja en `visible=false` con costo despreciable.
5. Sin regresiones en `SearchLightV2` ni en el resto de props que comparten
   `volumetric_cone.shader` (la extensión de máscara debe ser opcional y no cambiar el
   comportamiento sin máscara).
6. `python3 scripts/check_tracked_imports.py` y smoke de imports limpios.

## Out of Scope

- Modo "escáner" con lógica de gameplay (resaltar interactuables, revelar códigos,
  enemigos). Es solo el **efecto visual**; el escaneo funcional es backlog.
- Postprocesado, projector o cualquier segunda pasada de luz.
- Cargol trayendo gloo/láser (backlog, se introduce narrativamente después).
- Cambiar el puzzle de coolant o su dependencia del gloo (ver FD-266 / sótano).
