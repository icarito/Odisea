# FD-325: Controles unificados, ergonomía táctil y HUD diegético

**Status:** Plan aprobado; T1 en implementación.
**Priority:** Alta (el Ark-Run se juega con mando, teclado y touch; hoy los mismos
botones hacen cosas distintas según el dispositivo).
**Effort:** Medio (5 tareas T1–T5 en paralelo, sin solape de archivos).
**Created:** 2026-11-23
**Depends on:** FD-324 (Ark-Run vertical slice, Suit OS del slice, apps
`player:thrusters` / `player:rope` / `player:autonav`), FD-304 (hombros = slots
del HUD en gameplay), FD-296 (`hud_mode` / radial).
**Contrato técnico compartido:** `.operator-shared/specs/fd-325-controls-hud.md`
(fuente única para los workers T1–T5).

## 1. Problema

El Ark-Run mezcló dos sistemas de control que hoy se pisan:

1. **Los gatillos `LT`/`RT`** son el control de gameplay "de verdad" (Δv del
   propulsor y cuerda), pero además quedaron mapeados a los slots 2 y 4 del HUD
   (`player:thrusters` en `L2`, `player:rope` en `R2`, ver `ARK_RUN_DEFAULT_PINS`).
   Sostener `LT` para volar también *abre/acciona* el slot del HUD, y el
   `InputProviderV2` publica `hud_slot = 2|4` en gameplay: dos intentos para un
   solo dedo.
2. **Touch** no tiene control equivalente a `LT`/`RT`: los botones de acción son un
   bloque único abajo-derecha y no hay `IMPULSO`/`CUERDA` con la semántica de
   gatillo (mantener vs. toggle), ni feedback de Δv.
3. **HUD superior** no existe como vista unificada: el progreso vive disperso en
   `ArkRunHudOverlay` y en la app `ship:ark_nav`, y el jugador no tiene una lectura
   única de *dónde está* entre Puente y Motor, ni del perfil radial ni de la
   gravedad local con el giro.
4. **Feedback diegético** insuficiente: el impulso del propulsor y el tirón de la
   cuerda no se ven/sienten en el personaje; el anclaje asistido no tiene retícula
   ni badge que diga con qué dispositivo se enganchó.

## 2. Decisiones de diseño (4 bloques aprobados)

### Bloque 1 — Gatillos 100% gameplay; L1/R1 para slots rápidos

- `LT` (`thruster_boost`) y `RT` (`rope_grapple`) son **solo gameplay**: nunca
  disparan `hud_slot_*` en gameplay. El proveedor suprime los slots de los gatillos
  mientras `SuitOS.triggers_reserved_for_gameplay` está activo.
- `L1` → slot rápido **Linterna** (`slot_1`); `R1` → slot rápido **Autonavegador**
  (`slot_3`, `player:autonav`). Son los dos únicos hombros que accionan slots en
  gameplay.
- `Y`/`X` abren el **Modo HUD** con los 4 slots completos (radial). En `hud_mode`
  los cuatro slots (`slot_1..slot_4`) siguen funcionando completos: es una UI, no
  gameplay.
- Teclado: `E` y click derecho = `rope_grapple`; `Shift` en aire o cuerda, o `Q` =
  `thruster_boost`; `TAB` = `nav_assist`; `Backspace`/`F5` = reinicio.

### Bloque 2 — Touch ergonómico con zonas seguras

- En `MobileUI.tscn`: zonas seguras **abajo-izquierda** (`MoveJoystick`) y
  **abajo-derecha** (`ActionButtons`); la **franja superior es solo HUD** (ningún
  control de gameplay ahí).
- **Izquierda**: `IMPULSO` / `RETRAER` con anillo de Δv que *espeja* `LT`
  (mantener = empuje; el anillo consume `spin_thruster_dv_remaining`).
- **Derecha**: `CUERDA` / `SOLTAR` que *espeja* `RT`. Toque = enganchar (toggle);
  toque de nuevo **o salto** = soltar conservando el momento.
- **`AUTONAV`** arriba-derecha (fuera de la zona de acción, dentro de la franja
  HUD).
- Todo esto solo visible en `SPIN_REAL` (`GravityModes.Mode.SPIN_REAL == 4`).

### Bloque 3 — HUD superior unificado

- Una vista `ArkRunTopBarView` en la franja `y < 140 px`, reutilizada en pantalla
  completa y en la app `ship:ark_nav`.
- Barra longitudinal `[PUENTE] ══●══|══ [MOTOR]` con un **fantasma** (mejor corrida)
  además del marcador vivo.
- Perfil radial `HUB──TERRAZA──CASCO` y lectura de **gravedad con flecha a 45°**
  cuando hay `a_axial` de ignición.
- Dos chips de hombros `L1` / `R1` mostrando las apps rápidas.
- Sin el círculo plano anterior (`minimap` deja de ser un disco; el perfil radial
  reemplaza al punto polar).

### Bloque 4 — Diegética

- **Doble jet** en la mochila (partículas) + **arco segmentado Δv** junto a Elías,
  oculto al 100% de presupuesto en suelo.
- **Retícula magnética 2D** en el anclaje asistido, con **badge del último
  dispositivo** que enganchó (`RT` / `E` / toque).
- **Tether** con degradado cian → dorado mientras retrae.
- **FOV `+5°`** mientras el propulsor está activo y **audio sutil** de empuje/cuerda.

## 3. Contratos duros

1. **Determinismo.** Nada de estado de input nuevo en `_process`; el gameplay lee
   en `_physics_process`. Las acciones nuevas (`rope_grapple`, `thruster_boost`)
   se leen por polling con `InputMap.has_action` + `Input.is_action_pressed`, igual
   que el resto del proveedor. El badge del último dispositivo es **presentación**:
   no entra al replay.
2. **Un solo rig de cámara.** El `FOV +5°` se aplica como término del `CameraRig`
   existente (spring length/fov), nunca creando un rig nuevo. No hay salto de FOV:
   sube y baja con rampa durante el empuje.
3. **Touch es un espejo, no un modo paralelo.** Los botones táctiles sintetizan las
   **mismas** acciones (`thruster_boost`, `rope_grapple`, `nav_assist`) con
   `Input.action_press` vía `TouchActionButton.note_touch_action`, así el proveedor
   no distingue touch de mando.
4. **El modo HUD sigue completo.** Toda liberación de gatillos ocurre estrictamente
   en gameplay (`not SuitOS.is_hud_mode_active()`); dentro del radio de `hud_mode`
   los 4 slots funcionan.
5. **CI = Backend de tests.** Tests headless con el binario `platform=server` del
   release pinneado (`./runtest.sh`). No validar con X11 oculto.
6. **Escenas del slice, edición quirúrgica.** `MobileUI.tscn` y los `.tscn` del
   Ark-Run se editan por nodo; nunca se reserializa el archivo completo con `pack()`.
7. **Lo dudoso va detrás de un flag.** `triggers_reserved_for_gameplay` (default
   `true`) y `touch_toggle_mode` (default `false` en la clase, activado por la
   escena) permiten volver al comportamiento anterior sin revertir el FD.

## 4. Grafo de tareas T1–T5

| Tarea | Alcance | Módulo / archivos principales | Estado |
|-------|---------|-------------------------------|--------|
| **T1 — Input unificado** | Registrar `rope_grapple` / `thruster_boost`; liberar `LT`/`RT` de slots en gameplay; `SpinRopeInputV2` toggle touch + `jump` release; `ArkRunThrusterInput`/`SpinRopeInputV2` leen las acciones; `last_input_device`. | `project.godot`, `core_v2/input/InputProviderV2.gd`, `core_v2/autoloads/SuitOS.gd`, `core_v2/ui/hud/HudSlotGamepadV2.gd`, `core_v2/player/traversal/SpinRopeInputV2.gd`, `core_v2/levels/ark_run/ArkRunThrusterInput.gd`, `core_v2/tests/test_fd325_unified_input.gd` | **Esta tarea** |
| **T2 — Touch ergonómico** | Zonas seguras, `IMPULSO`/`RETRAER` + anillo Δv, `CUERDA`/`SOLTAR`, `AUTONAV`; visibilidad solo en `SPIN_REAL`. | `MobileUI.tscn`, `MobileUIManager.gd` | Pendiente |
| **T3 — HUD superior** | `ArkRunTopBarView` (barra con fantasma, perfil radial, gravedad 45°, chips L1/R1) en `y < 140 px`, reusable en `ship:ark_nav`. | `ArkRunHudOverlay.gd`, `ArkNavWidget.*`, nuevo `ArkRunTopBarView.*` | Pendiente |
| **T4 — Diegética** | Doble jet + arco Δv, retícula + badge, tether cian→dorado, FOV +5°, audio. | `ArkRunAnchorVisuals.gd`, `ArkRunSlice.*`, `ArkRunLiveLoop.gd` | Pendiente |
| **T5 — Integración y pulido** | Cierre, telemetría `last_input_device`, ajustes de balance, deploy al Anbernic. | Integración; toca todas las anteriores | Pendiente |

### Dependencias

- **T1 es prerequisito de T2 y T4**: T2 publica acciones que T1 ya registró; T4 lee
  `rope_grapple` / `thruster_boost` y el `last_input_device` para el badge.
- **T3 es independiente de T1** (solo presentación del HUD superior).
- **T5** depende de T1–T4.
- Los archivos de T2/T3/T4 están **prohibidos** para T1 y viceversa (ver §6).

## 5. Criterios de aceptación

- **T1**: `rope_grapple` y `thruster_boost` existen en `InputMap` con sus eventos;
  `L2`/`R2` no emiten `hud_slot` en gameplay con `triggers_reserved_for_gameplay`;
  `L1`/`R1` sí; `hud_mode` mantiene los 4 slots; touch toggle de cuerda engancha,
  mantiene con el dedo suelto y suelta con tap 2 o `jump` conservando velocidad;
  `get_active_input_device()` devuelve `"keyboard"` / `"gamepad"` / `"touch"`.
- **T2**–**T4**: definidos en el contrato compartido y sus propias tareas.

## 6. Archivos prohibidos al editar en paralelo

`MobileUI.tscn`, `MobileUIManager.gd`, `ArkRunHudOverlay.gd`, `ArkNavWidget.*`,
`ArkRunSlice.*`, `ArkRunLiveLoop.gd`, `WorldRotator.gd`, `CylinderRotator.gd`,
formato `.oys`. Cada tarea edita solo sus archivos permitidos; un cambio que
necesite otro archivo se coordina en el contrato compartido primero.

## 7. Referencias

- `.operator-shared/specs/fd-325-controls-hud.md` — contrato técnico compartido.
- `docs/features/FD-324_del_hub_al_motor.md` — vertical slice del Ark-Run.
- `docs/features/FD-323_spinframe_rotating_cylinder_physics.md` — `SPIN_REAL`.
- `AGENTS.md` §2.3 (cámara única), §5.3 (replay determinista), §6 (tests/CI).
