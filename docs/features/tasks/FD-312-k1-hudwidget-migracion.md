# FD-312 · K1 — Migrar los 5 widgets restantes a `HudWidget`

**Ejecutor:** KILO (`kilo/deepseek/deepseek-v4.1-flash`) · **Rama:** `docs/odiseaos-consolidacion`
**Spec:** `docs/odiseaos/MANUAL_DEL_TRIPULANTE.md` §3.2, §6 y §7

---

## Lea primero, en este orden

1. `core_v2/ui/hud/HudWidget.gd` — la clase base. **Ya existe. No la modifique.**
2. `core_v2/ui/hud/FlashlightWidget.gd` — **el ejemplo de referencia, ya migrado.**
   Copie ese patrón exactamente.
3. `core_v2/ui/OdiseaOSTheme.gd` — los tokens de color.
4. `docs/odiseaos/MANUAL_DEL_TRIPULANTE.md` §6 (código de color) y §7 (OFFLINE).

## Qué ya está verificado — no lo vuelva a investigar

- La base funciona: `test_flashlight_screen`, `test_suitos_widget_host`, `test_hud_mode`,
  `test_hud_drawer`, `test_suit_os`, `test_remote_control_home_hud` y
  `test_helmet_flashlight` pasan con `FlashlightWidget` ya migrado.
- El contrato con el host **no cambia**: `SuitOSWidgetHost` llama
  `update_snapshot(Dictionary)`. La base ya lo implementa.
- **No use `class_name` en archivos nuevos** y no agregue ninguno: en Godot 3 registrar
  un `class_name` exige que el editor reescriba `project.godot`. Los `class_name` que ya
  existen en los 5 widgets **se conservan tal cual**.
- La herencia va por ruta: `extends "res://core_v2/ui/hud/HudWidget.gd"`.
- `OdiseaOSTheme` está disponible como constante heredada de la base. **No agregue un
  `preload` de `OdiseaOSTheme` ni de `HudWidgetAction` en los hijos**: ya los hereda.

## OBJETIVO

Migrar estos 5 archivos a la base, sin cambiar lo que el jugador ve salvo por la tabla
de color de abajo:

- `core_v2/ui/hud/CargolWidget.gd`
- `core_v2/ui/hud/MultiToolWidget.gd`
- `core_v2/ui/hud/SystemStatusWidget.gd`
- `core_v2/ui/hud/HoloTerminalWidget.gd`
- `core_v2/ui/hud/CryoPodsWidget.gd`

## ARCHIVOS PERMITIDOS

Exactamente esos 5 `.gd`. Nada más.

## ARCHIVOS PROHIBIDOS

`core_v2/ui/hud/HudWidget.gd` · `core_v2/ui/OdiseaOSTheme.gd` ·
`core_v2/ui/hud/FlashlightWidget.gd` · `core_v2/ui/hud/SuitOSWidgetHost.gd` ·
`core_v2/ui/hud/HudModeOverlay.gd` · `core_v2/ui/hud/CryoPodWidget.gd` (singular —
**no** es lo mismo que `CryoPodsWidget.gd`) · `core_v2/ui/hud/InteractableSlotWidget.gd` ·
cualquier `.tscn` · cualquier archivo en `core_v2/tests/` · `project.godot` ·
`.github/` · cualquier archivo que no esté en ARCHIVOS PERMITIDOS.

## El patrón, exacto

Para cada archivo:

1. `extends PanelContainer` → `extends "res://core_v2/ui/hud/HudWidget.gd"`.
   El `class_name` de la línea siguiente **se queda como está**.
2. Borrar el `const HudWidgetAction = preload(...)` si lo tiene (lo hereda).
3. Borrar los `onready` de `_title_label` y `_status_dot` (los tiene la base).
   **Los demás `onready` se quedan.** Si alguno usa `$Ruta`, cámbielo a
   `get_node_or_null("Ruta")`.
4. Borrar `var _screen_id: String = ""` si lo tiene (lo tiene la base).
5. Borrar `func update_snapshot(...)` entero (lo tiene la base).
6. Borrar de `set_snapshot` las líneas que leen `title`, `source` e `id`, y la asignación
   de `_title_label.text` (los hace la base).
7. Renombrar `set_snapshot(snapshot)` → `_render(snapshot)`, y **borrar de ahí la rama
   `if source == "offline": ... return`**.
8. Mover el cuerpo de esa rama a un `func _render_offline() -> void:` nuevo.
   **Quite de ahí la línea que pinta el punto de gris**: la base ya lo hace.
9. Agregar `func default_title() -> String:` devolviendo, con `tr()`, el mismo texto que
   estaba como default de `snapshot.get("title", "...")`.
10. Si el widget hardcodea un id de pantalla al llamar `HudWidgetAction.perform`, agregar
    `func default_screen_id() -> String:` devolviendo ese id, y reemplazar la llamada por
    `_perform("<op>")`.
11. Si tiene `_ready()` con el guard `is_connected`, reemplazarlo por
    `_bind_button(<boton>, "<metodo>")`.
12. Reemplazar los `Color(...)` por tokens según la tabla de abajo, usando `_set_dot()`
    donde se pinte el punto de la cabecera.

## Tabla de color — úsela literalmente

| Archivo | Caso | Token |
|---|---|---|
| `SystemStatusWidget` | `STATE_OK` | `OdiseaOSTheme.STATE_NOMINAL` |
| `SystemStatusWidget` | `STATE_DEGRADADO` | `OdiseaOSTheme.STATE_CAUTION` |
| `SystemStatusWidget` | `STATE_FALLO` | `OdiseaOSTheme.STATE_ALARM` |
| `SystemStatusWidget` | default / `STATE_OFFLINE` | `OdiseaOSTheme.STATE_OFFLINE` |
| `CargolWidget` | 0 `LISTO` | `STATE_NOMINAL` |
| `CargolWidget` | 1 `CARGANDO EMP` | `STATE_CAUTION` |
| `CargolWidget` | 2 `DISPARANDO EMP` | `STATE_ACTIVE` |
| `CargolWidget` | 3 `RECARGANDO EMP` | `STATE_CAUTION` |
| `CargolWidget` | 4 `SEÑUELO ACTIVO` | `STATE_ACTIVE` |
| `CargolWidget` | 5 `CARGOL CAÍDO` | `STATE_ALARM` |
| `CargolWidget` | 6 `RETORNANDO` | `STATE_NOMINAL` |
| `CargolWidget` | valor inicial / default | `STATE_NOMINAL` |
| `MultiToolWidget` | modo `GLOO` | `STATE_ACTIVE` |
| `MultiToolWidget` | cualquier otro modo | `STATE_NOMINAL` |
| `HoloTerminalWidget` | `is_active` | `STATE_NOMINAL` |
| `HoloTerminalWidget` | en espera (no activo) | `STATE_OFFLINE` |
| cualquiera | rama offline | *no la pinte: la base ya pone `STATE_OFFLINE`* |

`CryoPodsWidget`: mapee por el mismo criterio del Manual §6 —
nominal = verde, atención = ámbar, alarma = rojo, activo = turquesa, inactivo/sin dato =
gris. **Si algún color de ese archivo no encaja en ninguno de los cinco, NO invente un
token: deje el `Color(...)` original, ponga un comentario `# TODO(token):` encima y
repórtelo al final.**

## REGLAS

- Godot 3.6 / GDScript 1.x: `yield()` no `await`, `connect()` con strings, sin `@onready`.
- **No cambie ningún texto que vaya adentro de `tr()`**, ni agregue ni quite `tr()`.
- **No toque `widget_snapshot()` ni la forma del diccionario.** La lectura es data pura
  serializable; meter un nodo rompe el control remoto.
- No cambie ninguna escena `.tscn`. Los paths de `get_node_or_null` se quedan igual.
- No renombre métodos públicos ni `class_name`.
- Un archivo a la vez. Después de cada archivo, corra su test (abajo) antes del siguiente.
- Si algo no encaja en el patrón, **pare y repórtelo**. No improvise.

## ACEPTACIÓN

Los tres comandos, en verde:

```bash
./.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_gd__core_v2_tests_test_cargol_screen_gd or test_gd__core_v2_tests_test_multitool_screen_gd or test_gd__core_v2_tests_test_system_status_screen_gd"
./.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_gd__core_v2_tests_test_cryopods_hudable_gd or test_gd__core_v2_tests_test_holoterminal_hudable_gd or test_gd__core_v2_tests_test_suitos_widget_host_gd"
./.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_gd__core_v2_tests_test_hud_mode_gd or test_gd__core_v2_tests_test_remote_control_home_hud_gd"
```

Y además:

```bash
# ningun literal de color debe quedar en los 5 archivos (salvo los marcados TODO(token))
grep -n "Color(" core_v2/ui/hud/{Cargol,MultiTool,SystemStatus,HoloTerminal,CryoPods}Widget.gd
# ninguno debe seguir extendiendo PanelContainer ni tener update_snapshot propio
grep -n "extends\|func update_snapshot" core_v2/ui/hud/{Cargol,MultiTool,SystemStatus,HoloTerminal,CryoPods}Widget.gd
```

El total de los 5 archivos tiene que **bajar** de 374 líneas (65+44+67+129+69). Si sube, algo se hizo mal.

## PROCEDIMIENTO

1. Leer los 4 archivos de la sección "Lea primero".
2. Migrar **un** widget. Empiece por `MultiToolWidget.gd` (el más chico).
3. Correr su test. Si falla, arreglar antes de seguir.
4. **CHECKPOINT 1 — deténgase y reporte** después de `MultiToolWidget` y
   `CargolWidget`: pegue el diff de los dos y el resultado del test.
5. Seguir con `SystemStatusWidget`, `HoloTerminalWidget`, `CryoPodsWidget`.
6. **CHECKPOINT 2 — deténgase y reporte**: los tres bloques de ACEPTACIÓN, el conteo
   de líneas antes/después por archivo, y cualquier `TODO(token)` que haya dejado.
7. **No commitee.** El diff lo reviso yo.

No improvise fases nuevas. No toque archivos fuera de ARCHIVOS PERMITIDOS.
