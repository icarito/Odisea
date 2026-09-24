# Sesión — Pulido iterativo (2026-09-24)

Doc de continuidad de una sesión **iterative-list-hacking**: el usuario suelta observaciones de a una,
se consolidan en plan, se ejecutan en tandas, y él prueba **local + Anbernic**. Este archivo es la
fuente de verdad para retomar con contexto fresco.

Skill del workflow: `.agents/skills/iterative-list-hacking/SKILL.md`.

## Estado git
- Último commit: `7cea9461` (T1–T6 + P2.2 + gate de input + comportamiento de mouse en pausa).
- Hay **~20 archivos modificados + 3 nuevos sin commitear** (pulido posterior al commit). No commitear
  hasta que el usuario lo pida.
- Nuevos: `core_v2/props/controls/HoloProjectorBeamV2.gd`, `core_v2/props/controls/HoloProjectorBeam.tscn`.

## Hecho y verificado (tests verdes)
1. **D-pad cámara**: rampa progresiva con curva calibrable (`data/curves/Digital_Camera_Accel.tres`,
   `InputProviderV2.gd`, `PlayerControllerV2.gd`). Solo rama digital.
2. **Linterna**: `spot_angle=32`; se monta al hombro **antes** de hacerse visible y espera si el
   esqueleto/cámara no están listos (`HelmetFlashlight.gd`). No aparece en los talones.
3. **Consola HUD**: cursor con proyección absoluta sobre la superficie (`HudModeOverlay.gd`).
4. **Criocápsula**: transición de cámara al `FocusedRig` vía `CinematicManager` (`CryoPodHUDable.gd`,
   `CryoPodTerminal.tscn transition_time=1.3`).
5. **Pausa pasiva**: órbita automática con zoom elíptico real (`CinematicManager.gd`,
   `PlayerControllerV2.set_idle_orbit_zoom/set_idle_orbit_camera_active`), split de
   `PauseManager.resume()` diferido, congelado de `PilotAnimatorV2`, head-look siguiendo la cámara
   (no-low-end) vía `PilotAnimatorV2.update_head_look_for_orbit`.
6. **Start/Select**: Start = toggle pausa pasiva (nunca abre menú); Select = libera mouse (y
   **debería recapturar**, ver B7). Gate global de puntero liberado en `InputProviderV2`.
7. **PerformanceMonitor**: no alerta FPS sin foco.
8. **Cursor en transición** a pantalla holográfica: oculto hasta que hay movimiento.
9. **Criopod emisores**: `Smoke`/`Sparks` arrancan apagados; leak solo al abrir (5 s); chispas burst
   único al operar la escotilla desde la GUI (`Criopod_vert.tscn`, `SparkEmitterV2.gd`,
   `CryoPodHUDable.gd`).
10. **Cursor del HUD de Criopod más suave**: se fuerza `UPDATE_ALWAYS` mientras el HUD presta el
    Viewport y el terminal no lo pisa (`HoloTerminalHUDable.gd`, `HoloTerminalV2.gd`).
11. **Haz del holograma (A)**: `HoloProjectorBeamV2.gd` (pirámide additive con
    `volumetric_cone.shader`, `emitting` compatible, low-tier atenúa/simplifica) instanciado como
    `HoloParticles` en `WallTerminal`, `TableTerminal`, `HoloTerminalV2`, `HelmetHUD`,
    `ElevatorFloorSelector`; overrides limpiados en `CryoPodTerminal`/`DomeIntroCryoDiagnosticsDisplay`;
    `ElevatorFloorSelector.gd` pasó a duck-typing; guards `is CPUParticles` en los flujos de partículas
    de `HoloTerminalV2`/`TerminalHUDBridge`. **Falta validación visual en device.**

Tests usados: `pytest tests/test_odisea_runner.py -q -k "<substr>"` (ver skill). Última corrida del haz:
`holoterminal_ui_bridge, elevator_unit, cryopod_terminal` → 3/3.

## Plan pendiente (decisiones ya tomadas)
- **A. Haz**: pirámide proyector→pantalla (hecho); validar look en low-end/Anbernic.
- **B1. Todo el Criopod interactuable** → al interactuar, activa su Pantalla. Hoy solo el terminal
  tiene collider chico (`CryoPodTerminal.tscn`); la carcasa (`DisplayCaseBody`) no es interactuable.
  Enfoque: área `InteractableBaseV2` que cubra el pod y delegue a `terminal.interact()/focus()`.
- **B2. Widget "Abrir" con transición de cámara**: el HUD **se cierra igual que hoy**. El botón del
  widget (`CryoPodWidget`) ya llama `toggle_hatch`; agregar op `toggle_hatch_watch` que pida el
  `FocusedRig` por `CinematicManager` para ver la acción y lo libere al terminar.
- **B3. Widgets semi-transparentes** (alpha ~0.7; en `GLES3VendorGate.is_low_tier()` → opaco).
  Fuentes: revisar legibilidad en chico. Candidatas: `Silkscreen-Regular/Bold` para labels;
  `Ac437_OlivettiThin_8x16` (ya en `TinyFont.tres`) para terminal/consola. Hoy widgets/pantallas usan
  `SyneMono_Prologue_20` (flojo en chico). **B3.deriv**: mejorar el font del `DebugConsole` del HUD.
- **B4. Auto-hide de widgets en gameplay** (no HUD): tras la misma inactividad que `MobileUI`
  (`MobileUIManager.touch_idle_timeout`, 15 s), fade out **muy lento** del widget de contexto/ slots;
  reset con actividad de cámara/player/HUD. Implementar en `SuitOSWidgetHost`.
- **B5. Drag con Joypad**:
  - B5a: el asa de la Pantalla con mouse virtual/cursor unificado (hoy usa `event.position`; además no
    marca `VirtualMouse.set_dragging(true)` en ese drag).
  - B5b: el Drawer no permite drag con stick/hombros como el radial (`_drive_drawer_shoulder_drag` vs
    `_stick_drag_armed`/`_drive_stick_drag`).
- **B6. Jump = back en UI** (HUD overlay, menú de pausa, popups, pantallas con foco). No afecta gameplay.
- **B7. SELECT recaptura** si el puntero está liberado (toggle release/capture; nunca pausa/despausa).
  Cambia lo antes acordado ("solo liberar") → actualizar test de semántica.
- **B8. Pausa pasiva por START sin liberar/mostrar el cursor** hasta que haya movimiento.

## Ownership map para despacho paralelo (sin solape de archivos)
- **Agente P (pausa/input)**: B7, B8, B6 parte `PauseMenu`. Archivos: `PauseManager.gd`, `PauseMenu.gd`,
  `test_pause_menu_minimal.gd`.
- **Agente W (widgets look)**: B3 (transparencia + fuentes) y B3.deriv. Archivos: `HudViewMount.gd`,
  `CryoPodWidget.gd/.tscn`, `CryoPodUI.gd`, tema/fuentes; `DebugConsoleManager.gd`/`OYSShell` para el font.
- **Agente F (fade gameplay)**: B4. Archivos: `SuitOSWidgetHost.gd` (leer `MobileUIManager` para el timeout).
- **Agente D (drag)**: B5a/B5b, B6 parte `HudModeOverlay`. Archivos: `HudModeOverlay.gd`.
- **Agente C (criopod)**: B1, B2. Archivos: `CryoPodHUDable.gd`, `Criopod_vert.tscn`, `CryoPodTerminal.tscn`.

Regla: los agentes **no commitean**, corren solo sus tests puntuales y reportan archivos/diff/test/blocker.

## Cómo retomar
1. Leer este doc + el skill `iterative-list-hacking`.
2. `git status` y `git diff` para ver el estado real de los agentes.
3. Correr los tests de los sistemas tocados; arreglar cualquier `Parse Error` (ojo: GDScript 1.x no
   infiere tipo desde `export`).
4. Cuando el usuario apruebe: commit + push (nightly) y luego build/deploy del PCK (ver skill).
5. Seguir el orden: **A validar → B7/B6 → B5a/B5b → B3/B4 → B1/B2 → B8**.

## Pendientes de validación del usuario en device- Look del haz del holograma (pirámide) en low-end/Anbernic.
- Órbita + zoom de la pausa pasiva, y que START no libere el cursor.
- Semántica Start/Select y "Jump = back".
- Transparencia de widgets y legibilidad de fuentes.

## Subagentes despachados (2026-09-24, background)
Ownership disjunto; no commitean; corren tests puntuales y reportan. IDs de sesión:
- **P (pausa/input)**: B7 + B8 + B6(PauseMenu) — `ses_f2eecf29fffeTSDIgbKsdTO97T`
- **W (widgets look/fonts)**: B3 + B3.deriv — `ses_f2eece527ffeySASrrSVDC5p0A`
- **F (fade gameplay)**: B4 — `ses_f2eecda0bffeKdh7wtsN3sEnKw`
- **D (drag)**: B5a/B5b + B6(HudModeOverlay) — `ses_f2eecce4effeDzrvvJ2Y1kdH5c`
- **C (criopod)**: B1 + B2 — `ses_f2eecc325ffeQIFj1W5PQuItNp`

Al retomar: `git status`/`git diff`, revisar los diffs de cada agente contra este ownership map,
correr los tests de cada sistema, y recién ahí commit/push + build/deploy.

### Resultados
- **F (B4) — ✅ hecho.** `SuitOSWidgetHost.gd` (+`_idle_*`, `set_process(true)`, hooks `_note_activity`)
  y nuevo `test_widget_idle_fade.gd`. Timeout dinámico desde `MobileUIManager.touch_idle_timeout`
  (15 s, sin hardcodear; **no** usa el branch desktop de 2 s). Fade out 3.5 s / in 0.25 s sobre
  `_widget_root.modulate.a`. Actividad = `SessionManager.player.velocity` + cualquier `InputEvent` +
  gestos de HUD. Gate de gameplay: off en pausa/HUD/cinemática/popup. Tests:
  `hud_mode, widget, remote_control_home_hud` → 4 passed.
- **P (B6/B7/B8) — ✅ hecho.** `PauseManager._release_select_control` → `_toggle_select_control`
  (recaptura si está liberado); `_reveal_passive_menu` libera/muestra el cursor recién al revelar;
  `PauseMenu.set_minimal` saca/pone el requester (`_set_cursor_requester`) para que el modo minimal
  no cuente; `PauseMenu._is_back_event` trata Jump (B, `JOY_BUTTON_1`) como `ui_cancel`, excluyendo
  Select y botón derecho. Tests nuevos en `test_pause_menu_minimal.gd`
  (`test_select_toggles_the_pointer_between_release_and_recapture`,
  `test_start_passive_pause_does_not_release_or_request_the_cursor`,
  `test_jump_button_is_back_but_select_and_right_click_are_not`). `pause_menu_minimal` + `pointer_release_gate`
  → passed.
  **Rename propagado**: `rg "_release_select_control" core_v2` → 0 usos (riesgo de integración cerrado).
- **W (B3) — ✅ hecho (pendiente A/B visual).** `HudViewMount.widget_alpha()` = 0.7 / 1.0 en low tier;
  `apply_widget_panel_alpha`; CryoPodWidget panel 0.92→0.7; presenter glass cap 0.7. Fuentes: cuerpo de
  widgets/pantallas → `Silkscreen-Regular` (vía `CryoPodUI.small_font`), consola → `TinyFont.tres`
  (`Ac437_OlivettiThin_8x16`), `SHELL_FONT_SIZE 28→22`. Tests de terminal pasan; `test_hud_mode` quedó
  bloqueado un rato por un parse transitorio de D (ya resuelto). Candidatos A/B y follow-ups abajo.
- **D (B5/B6) — ✅ hecho.** B5a cursor unificado (`_unified_cursor_position`) para hit-test/drag del asa +
  `VirtualMouse.set_dragging`; B5b drag del drawer con stick; B6 Jump = back en overlay (y salir de
  pantalla enfocada con el edge B). Tests: `hud_mode, virtual_mouse, remote_control_home_hud, pointer_release_gate`
  → 4/4. Pendiente validación en Anbernic (arming del stick en drawer).
- **C (B1/B2) — ✅ hecho.**
  - B1: agrandó el collider del terminal en `CryoPodTerminal.tscn` (`BoxShape 0.84,1.55,0.86` sobre
    `InteractableEntity/CollisionShape`) para cubrir la cápsula; mantuvo **un solo** interactuable
    (lo exige `test_pod_has_a_single_interactable_covering_the_capsule`). Delegación sin proxy.
  - B2: en `CryoPodHUDable.perform_action("toggle_hatch")` setea `_hatch_watch_pending`; al cerrar el
    HUD, `_maybe_start_hatch_watch()` pide el `FocusedRig` por `_request_focus_camera_rig()` y lo libera
    cuando la animación termina (`_release_hatch_watch_camera`). Skippea si corre un OYS `legacy_direct`.
  - Tests: `cryopod_terminal, cryopods_hudable, ringhub_wakeup, holoterminal_hudable` → 4 passed;
    + nuevo `test_cryopod_pod_interaction.gd` → 5 passed.
  - **Pendiente/incertidumbre**: la rama "si ya está activo → `focus()`" no se implementó (requiere
    `HoloTerminalV2.gd`); B2 necesita validación visual de la transición en vivo.
### Follow-ups de B3 (del agente W)
- Slot widgets siguen opacos: `SuitOSWidgetHost._widget_panel_style()` (WIDGET_BG a=1.0). Para cubrirlos,
  llamar `HudViewMount.apply_widget_panel_alpha(overlay)` tras el `add_stylebox_override("panel", ...)`.
- A/B candidatos: panel alpha 0.70 vs 0.62 vs 0.80; Silkscreen vs Ac437 en cuerpos; BPM 56 con Silkscreen
  vs `Heading_Font`; `SHELL_FONT_SIZE` 22 vs 26 vs 28; holograma 2D remoto sin tocar.

## Nuevos items (ronda 2 — solo anotados, performance-first)
> Restricción explícita del usuario: **somos CPU-limited**; nada de sumar meshes ni overdraw sin gate low-end.

- **C1. Vidrios demasiado claros en la versión flat (low end).** En modo flat el vidrio usa
  `FlatFakeTransparent.shader` / `FlatFakeTransparentDoubleSided.shader` (`GLES3VendorGate.gd:29-32`);
  el brillo ambiente del modo flat sale de `_flat_ambient` (`:103`, `:217`). Bajar el nivel del vidrio
  (alpha/emisión) solo en flat/low-end, sin tocar la versión normal.
- **C2. Falta el PersonCard en low end.** Existe hoy como `PersonCards` (`MultiMeshInstance` en
  `RingHub_Criopods*_visual.tscn`) y `PersonCard2` (`MeshInstance` en `CriopodParallax*.tscn` /
  `CriopodParallaxFull.tscn`), con texturas `PersonCards.exr/.png`. En flat/low-end desaparece. Buscar
  un reemplazo barato (p. ej. **un quad con textura billboard/fake-parallax**, reusando `FlatFake`
  transparente) en vez de sumar meshes; decidir si se hace con lo que ya existe o un único mesh
  compartido.
- **C3. Traje emisivo de Elías debe responder al ambiente.** Hoy `models/Pilot.glb` con material propio
  (y `core_v2/player/shaders/pilot_damage.shader`); el traje emisivo no se oscurece en zonas oscuras.
  Objetivo: modular su emisión/albedo según el ambiente (o al menos oscurecerlo si el `Environment` es
  oscuro), idealmente reusando `_flat_ambient`/el promedio de ambiente que ya calcula `GLES3VendorGate`.
  Requiere investigar cómo se overridea el material del piloto (glb → material/shaders).
- **C4. Mesh de la linterna negro en flat/low-end — ✅ implementado.** El mesh emisivo se llama
  `Emitter` y `GLES3VendorGate._keeps_own_material` matcheaba solo el **nombre del nodo**, así que el
  aplanado le quitaba la emisión y quedaba negro. Fix: el chequeo ahora incluye también el **nombre del
  padre** (`Emitter` → padre `HelmetFlashlight`). Tests `flashlight_screen, gles3_vendor_gate,
  helmet_flashlight` → 3/3.

## Cómo retomar

### Riesgo de integración detectado
F vio en una corrida intermedia: `Parse Error: The method "_release_select_control" isn't declared`
desde `HudModeOverlay.gd`. `_release_select_control` vive en `PauseManager.gd` (agente P, B7). Si P
lo renombra/elimina, hay que actualizar **todos** los llamadores (HudModeOverlay y cualquier otro).
Verificar en la integración: `rg -n "_release_select_control" core_v2`.
