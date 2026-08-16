# FD-260: Signage — configuración y legibilidad

**Status:** In Progress
**Priority:** Medium
**Effort:** Small
**Created:** 2026-08-15
**Completed:** -

## Problem

`core_v2/props/signage/SignagePanel.gd` (el sistema ligero de letreros del
FD-227) tiene limitaciones que impiden usarlo en niveles reales:

1. **Fuente hardcodeada a un archivo que no existe** — `res://assets/fonts/terminal.ttf`
   no está en el repo; cae en fallback silencioso a `Ac437_OlivettiThin_8x16.ttf`.
   La fuente no es configurable.
2. **Autofit frágil** — el tamaño de fuente sale de una heurística
   (`longest_word > 4` ⇒ encoge). No mide ancho/alto real: texto largo o
   multipalabra se clipea de los bordes.
3. **Aspect-ratio mal** — viewport `512×256` (2:1) vs QuadMesh `1.2×0.72`
   (5:3) ⇒ el texto se distorsiona (estirado horizontal).
4. **Configurabilidad limitada** — sin `font_size` explícito, sin alineación,
   sin case (mayúsculas), sin padding, sin outline, sin borde. Radio de
   interacción hardcodeado (`SphereShape` 2.0 en el `.tscn`).
5. **Paletas divergentes** — `SignagePanel` y `AreaInfoScreen` definen colores
   de preset *distintos* para el mismo nombre (ej. `info`/`warning`).
6. **Ningún nivel usa el sistema** — base sin validar.

## Solution

Refactorizar `SignagePanel.gd` para que un letrero se configure íntegro desde
el Inspector y el texto quepa siempre (autofit real, determinista y testeado).
**Sin tocar el aspecto final** (hues, glow, font "bonita"): eso se calibra
local con capturas, no se delega.

### Considered Options

- **A. Refactor de SignagePanel (elegida)** — acota el cambio a un archivo,
  alinea con el patrón `InteractableBaseV2`/`AreaInfoScreen` y es testeable.
- **B. Unificar SignagePanel + AreaInfoScreen** — descartada por scope: son dos
  sistemas con stacks de interacción distintos; unificar ahora es churn.
- **C. Reescribir desde cero** — descartada: el generador de textura
  Viewport+Label ya funciona; solo le falta configuración y medición.

## Files to Modify

- `core_v2/props/signage/SignagePanel.gd` (modify)
- `core_v2/tests/test_signage_config.gd` (new)

Prohibidos: cualquier `.tscn`, `project.godot`, `AreaInfoScreen.*`,
`core_v2/props/helmet_view/neon_sign/**`, `scenes/**`, `core_v2/levels/**`.

## Implementation Spec (lo que Jules implementa)

Todo en `SignagePanel.gd`, sin tocar el `.tscn`.

1. `export(DynamicFont) var font: DynamicFont = null` — `null` ⇒ default
   `SyneMono-Regular` (carga desde `res://assets/fonts/SyneMono-Regular.ttf`,
   que sí existe). Fallback determinista y testeable; **nunca rutas
   hardcodeadas a archivos ausentes**.
2. `export(int, 0, 256) var font_size := 0` — `0` = auto. **Autofit real**:
   medir con `font.get_string_size(text)` y bajar el tamaño hasta que
   `ancho <= viewport.x - 2*padding` **y** `alto <= viewport.y - 2*padding`.
3. `export(int) var alignment := Label.ALIGN_CENTER` (LEFT/CENTER/RIGHT) y
   `export(int) var case_mode := 0` (0=NONE, 1=UPPER, 2=LOWER). Aplicar el
   case antes de medir.
4. `export(float) var padding := 8.0` — margen interno en px del viewport.
5. `export(Color) var outline_color := Color(0,0,0,0.6)` y
   `export(int) var outline_size := 0` — sin outline si `outline_size == 0`.
6. `export(bool) var border_enabled := false`, `export(Color) var border_color`,
   `export(float) var border_width := 2.0` — borde (ReferenceRect) detrás del
   Label, solo si `border_enabled`.
7. `export(float) var interaction_radius := 2.0` — en `_ready`, aplicado al
   `CollisionShape` del nodo `Area` (SphereShape), sin editar el `.tscn`.
8. **Aspect-ratio**: cambiar el default de `viewport_size` a `(512, 307)` para
   respetar el aspect 5:3 del QuadMesh (1.2×0.72). Documentar en el export que
   sobrescribir `viewport_size` implica aceptar estiramiento de textura.
9. **Presets canónicos** en una sola constante `COLOR_PRESETS`
   (warning/danger/info/terminal/hologram), alineados con los de
   `AreaInfoScreen`:
   - `warning` `#FF8800`, `danger` `#FF2200`, `info` `#00FFFF`,
     `terminal` `#00FF88`, `hologram` `#00CCFF`.
   Documentar el mapeo color→uso en un comentario.
10. `face_player`: guard si `get_viewport().get_camera()` es null (headless,
    evita crash en test runner).
11. **Determinismo**: cero `randf`/`randi`/`get_ticks_msec` en gameplay. La
    oscilación holográfica es visual-only en `_process` (ya lo es). Misma
    config ⇒ misma dimensión de textura.

## Verification (Acceptance)

`./runtest.sh -a ./core_v2/tests/test_signage_config.gd` en verde:

1. Preset → Color exacto para los 5 presets (warning/danger/info/terminal/hologram).
2. Font ausente (`null`) ⇒ default `SyneMono-Regular` existe y carga.
3. Autofit: para `["SALIDA", "PELIGRO", "SOLO PERSONAL AUTORIZADO",
   "DESPRESURIZADO", "SECTOR EN CUARENTENA"]` el texto cabe
   (`get_string_size` dentro de viewport menos padding).
4. Setters (`text`, `color_preset`, `font_size`, `alignment`) tras `_ready`
   no crashean y actualizan la textura.
5. `is_interactive == false` ⇒ `Area` no monitoriza; `true` ⇒ radio aplicado
   al CollisionShape.
6. Determinismo: misma config ⇒ misma dimensión de textura.

## Out of Scope (backlog)

- Unificar con `AreaInfoScreen` / el dashboard (`FD-227-dashboard-ux-redesign`).
- Iconos/glifos, texto multicolor, fuentes "bonitas", glow/hues final.
- Integración en niveles reales (se hará al diseñar el Acto I).

## Conventions

Godot 3.6 / GDScript 1.x (`yield` no `await`, `onready`,
`connect("sig", self, "_m")`). Tipado estático, miembros `_`, `export`
documentados. Todo en `core_v2/`. GLES2: sin `SCREEN_TEXTURE`, sin nodo
`Particles`.
