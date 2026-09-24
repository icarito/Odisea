# Sesión — Pulido iterativo ronda 3 (2026-09-24)

Doc de continuidad de una sesión **iterative-list-hacking**. El usuario suelta observaciones de a una;
se anclan a `archivo:línea`, se consolidan en plan, se delegan por clusters con archivos disjuntos, y
él prueba local + Anbernic. Fuente de verdad para retomar con contexto fresco.

Skill: `.agents/skills/iterative-list-hacking/SKILL.md`. Comando: `/polish`.

## Observaciones (O1..O12) y decisiones

| # | Observación | Decisión |
|---|---|---|
| O1 | Head-look en órbita de pausa salió al revés | Delante: mirar a la **posición** de la cámara. Detrás: **congelar la pose del momento de pausar** (no seguir el forward). |
| O2 | Touch: no se puede salir de la pausa pasiva | Double tap **reanuda directo** (como clic izq. desktop). Ventana 300 ms / 40 px. |
| O3 | Drag del drawer al radial; "nada es estrellitas" | Sin estrellitas/partículas. Favoritear = botón existente **o** drag al radial; con el botón, el ítem debe **aparecer/desaparecer del radial** al instante. |
| O4 | Mouse virtual con joypad + click con interactuar en pantallas HUD | Stick mueve el cursor virtual; `interact` (F / `JOY_BUTTON_2`) = click izquierdo. |
| O5 | 60 s de inactividad → fade de música + pausa pasiva | 60 s sin input **y** jugador quieto; fade BGM ~4 s; luego pausa pasiva actual (START). |
| O6 | Fade de la UI mobile parece instantáneo | Agregar fade real (out ~0.5 s / in ~0.15 s). **Sin fade en low-tier/flat si es caro.** |
| O7 | Pared del domo de otro color que el piso | Pendiente (preguntas). |
| O8 | Fakeshadow no se nota en piso oscuro | Pendiente (preguntas). |
| O9 | Cámara un poco más abajo por default | Pendiente (preguntas). |
| O10 | Barandas de scaffold walkways naranjas | Pendiente (preguntas). Requiere re-bake. |
| O11 | Ocultar el mouse virtual cuando el input es touch | Pendiente (preguntas). |
| O12 | Brillo Android forzado a 60%: suavizar / desactivar en menús | Pendiente (preguntas). Java nativo + plugin. |
| O13 | El drawer debe ser arrastrable en touch (solo el label al slot) | Verificar/corregir el touch drag; el ghost ya es `Label`. |
| O14 | El asa dragable debe arrastrar un label, no el protowidget azul | Reemplazar `_capture_drag_mesh()` por el ghost `Label` del drawer. |

## Anclajes clave (archivo:línea)
- O1: `core_v2/actors/PilotAnimatorV2.gd:848-908` (`_update_head_look` :848-894, `update_head_look_for_orbit` :904-908; aim = forward cámara :871; gate `aim.dot(fwd)>0` :878; clamps :78-79).
- O2/O5: `core_v2/autoloads/PauseManager.gd:196-204,217-221,240-300,399-420`; `AudioManager.gd:426-440` (`fade_out_current_bgm`).
- O3/O4: `core_v2/ui/hud/HudModeOverlay.gd` (drawer drag :2026-2222; `_drop_option` :840-859; `_open_drawer` :1169-1192), `core_v2/ui/hud/SuitOSDrawer.gd` (estrella :229-270,327-359), `core_v2/ui/VirtualMouse.gd:345-398` (joypad A/B; `interact` NO cableado), `core_v2/ui/radial/RadialSelectorV2.gd`.
- O6: `core_v2/autoloads/MobileUIManager.gd:114-135,237-267,307-323`; fade de widgets (otro sistema) `SuitOSWidgetHost.gd:60-66,323-355`.
- O7/O10: `core_v2/levels/interiors/DomeIntro_IndustrialRailing.tscn:9-10` (rail naranja), `DomeIntro_ScaffoldSource.tscn:229-250` (`rebuild_baked_items`), `core_v2/tools/RadialScatter.gd:445-486`; bakers `tools/bake_scaffold_walkways.gd`, `tools/bake_dome_terrace_v2.gd`, `tools/bake_dome_interior_lowpoly.gd`, `tools/bake_ringhub_floor.gd`.
- O8/O9: `core_v2/visual/FakeShadow.gd`, `materials/shadow/FakeShadowShader.tres` (blend_mix negro, alpha fijo :40,55), `core_v2/actors/Pilot_v2.tscn:247-258,287-297` (Pitch ≈ +4.5°, SpringArm Rx(-10°)), `core_v2/player/PlayerControllerV2.gd:156` (`pitch := 0.0`).
- O11: `core_v2/ui/VirtualMouse.gd` (SIN manejo de touch; touch entra por `InputEventMouseMotion` :348-352), `MobileUIManager.is_pointer_from_touch()` :189-190, `InputProviderV2.pointer_is_from_touch()` :112-118.
- O12: `android/build/src/com/godot/game/GodotApp.java:57,88-96` (`BRIGHTNESS_FLOOR=0.6`, `screenBrightness=max(system,0.6)` en `onCreate`); plugin pattern `OdiseaUpdater` + `AndroidManifest.xml:44-49` → `Engine.get_singleton(...)`.

## Ownership map y despacho

| Cluster | Obs. | Archivos | Estado |
|---|---|---|---|
| A | O1 | `PilotAnimatorV2.gd` + test | ✅ hecho (`test_pilot_orbit_head_look` 1 passed) `ses_f2e72ce59ffeHz2IMiNhSUAS7e` |
| B | O2, O5 | `PauseManager.gd`, `PauseMenu.gd`, `AudioManager.gd` + test | ✅ hecho (15/15) `ses_f2e72bef2ffewmdyTfaP6Ufp5U` |
| C1 | O3, O13, O14 | `HudModeOverlay.gd`, `SuitOSDrawer.gd` + test | ✅ hecho (106 casos, 0 failed) `ses_f2e6ee026ffeOlA9FAy0xcr1f6` |
| C2 | O4, O11 | `VirtualMouse.gd`, `project.godot` + test | ✅ hecho (13/13 + 2 regresión) `ses_f2e6ec986ffek00eXJQsiH9bZr` |
| D | O6 | `MobileUIManager.gd`, `MobileUI.gd/.tscn` + test | ✅ hecho (8/8 + regresiones) `ses_f2e72b140ffez0fUSZpJk15OSg` |
| E | O8, O9 | `FakeShadow.gd`, `FakeShadowShader.tres`, `Pilot_v2.tscn`, `PlayerControllerV2.gd` | bloqueado por O8/O9 (preguntas) |
| F | O7, O10 | bakers + `DomeIntro_IndustrialRailing.tscn` + materiales | bloqueado + **serializado** (re-bake) |
| G | O12 | `GodotApp.java`, plugin nuevo, `AndroidManifest.xml`, GDScript de escena | bloqueado + **serializado** (Java/device) |

Regla: los subagentes **no commitean**, corren solo sus tests puntuales y reportan archivos/diff/test/blocker.

## Preguntas pendientes (7-12)
- O7: ¿`RingHub_Level` (flat/Anbernic) o `Dome_Base`? ¿"pared" = `DomeShell`?
- O8: ¿solución barata adaptativa low-tier (alpha + rim) o igual en desktop?
- O9: ¿pitch horneado en `Pilot_v2.tscn` (~+5°, A/B 5/8°)?
- O10: ¿unificar `DomeIntro_IndustrialRailing.tscn` a amarillo + re-hornear Dome_Intro y RingHub? ¿hub de Dome_Intro también?
- O11: ¿cursor oculto si el último input es touch, salvo "mouse libre" (pointer released) por joypad?
- O12: ¿suavizar piso (A) o respetar sistema + toggle (B)? ¿soltar en menús (C)? ¿toggle de usuario?

## Cómo retomar
1. Leer este doc + el skill `iterative-list-hacking`.
2. `git status` / `git diff` para ver el estado real de los agentes (no commitean).
3. Correr los tests de los sistemas tocados; separar `Parse Error` ajenos en `./reports/gdunit_runner.log`.
4. Con OK del usuario: commit + push (nightly), build PCK ARM64 y deploy al Anbernic (ver skill).
5. Falta cerrar F (re-bake) y G (Android) al final, serializados.

## Ronda 3b — devoluciones en device (mismo día)

| # | Observación | Estado |
|---|---|---|
| O1r | Órbita: el cuello se dobla demasiado y con brusquedad | ✅ blend `smoothstep` (sin salto de hemisferio) + tope pitch 20° + lerp ×0.5. `ses_f2e5265aaffe991r5Sx17fzHeu` |
| O11r | Touchscreen desktop sigue mostrando el cursor; holoterminal de RingHub queda trabada | corriendo `ses_f2e524d4fffeCLVprGSZaQ12BR` (VirtualMouse/MobileUIManager/HUD/holoterminal) |
| O13r | Quitar estrellas de la UI; drag al radial muestra el radial (fade) y desvanece el drawer; la lista debe scrollear arrastrando; bajar la "resistencia" del mouse | **pendiente de respuestas** (abajo) |
| O15 | En pausa pasiva, SELECT debe abrir el menú de pausa | ✅ `_reveal_passive_menu()` con pausa pasiva; gameplay sigue alternando puntero. Test nuevo (16/16) `ses_f2e4ebf50ffeujK0BJ3OsGKL63` |
| O16 | "MENÚ PRINCIPAL" sin traducir | ❌ **falso positivo mío**: los `.translation` son PHashTranslation (guardan hashes+valores, no las claves), por eso el grep del binario no probaba nada. El engine confirma que resuelve en los 7 idiomas (en→MAIN MENU). Guard nuevo `core_v2/tests/test_i18n.gd` (330 claves, 0 faltantes). Probable causa real: el PCK viejo del device, previo a la regeneración |

O13r resuelto: (a) sacar solo el dibujo/zona de la estrella del drawer; favoritear = drag-al-radial + X del mando; (b) la "resistencia" excesiva es el **paso de la rueda del mouse** (`_drawer.step_focus(±1)` en `HudModeOverlay.gd:2091-2094`) → bajarlo a la mitad o menos (scroll suave, no salto de fila entera); (c) al arrastrar el label sobre la zona del radial, el radial **vuelve a aparecer** (con animación) y el drawer se desvanece; soltar ahí = favorito **sin quitarlo** del drawer, con una animación que deje claro qué pasó.

| O17 | ENTER debe elegir la opción highlighted; toda la UI debería usar `ui_accept` | pendiente (va con O13r: `HudModeOverlay.gd`). `ui_accept` ya mapea ENTER/KP_ENTER/JOY0/JOY11; el radial lo maneja (`:785`), el drawer no |
| O18 | Device (Anbernic): el drawer es inutilizable; oprimir el botón del joystick **activa el primer ítem (Consola) al toque** | pendiente (va con O13r/O17). Causa probable: la misma pulsación que abre el drawer (seleccionar el hub del radial → `_open_drawer`) se procesa además como click en el drawer y el release acciona la fila enfocada (0 = Consola). Path en `HudModeOverlay._drive_drawer`/`_drawer_pointer_input`; bloqueado por O11r |

Nota: O11r y O13r tocan `HudModeOverlay.gd` → O13r se despacha **después** de O11r (serializado).
