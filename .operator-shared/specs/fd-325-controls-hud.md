# FD-325 — contrato técnico compartido: controles unificados, touch y HUD diegético

Fuente única para los workers T1–T5. Si una tarea necesita algo distinto, se
cambia aquí primero y luego en el código. Diseño, decisiones y grafo completo:
`docs/features/FD-325_unified_controls_touch_diegetic_hud.md`.

## 1. Acciones oficiales (T1 — registradas en `project.godot`)

| Acción | Semántica | Eventos | Leída por |
|--------|-----------|---------|-----------|
| `rope_grapple` | Cuerda (enganchar / mantener) | `KEY_E`, click derecho, `JOY_R2` (botón), `JOY_ANALOG_R2` (eje) | `SpinRopeInputV2` |
| `thruster_boost` | Propulsor (Δv) | `KEY_SHIFT`, `KEY_Q`, `JOY_L2` (botón), `JOY_ANALOG_L2` (eje) | `ArkRunThrusterInput` |
| `nav_assist` | Autonavegador (mantener) | `TAB` (+ `SLOT R1` en el Ark-Run) | `InputProviderV2` / overlay |
| `hud_mode` | Abrir Modo HUD (radial 4 slots) | `X` / `Y` gamepad / click derecho | `SuitOS._input` |
| `slot_1..slot_4` | Slots del HUD (solo gameplay: L1/R1; en HUD: los 4) | teclas `1..4` + hombros | `InputProviderV2` |

Reinicio de la corrida: `Backspace` / `F5` (ya vive en `ArkRunLiveLoop.gd`; no se
duplica como acción).

## 2. Regla de liberación de gatillos en gameplay (T1)

- `SuitOS.triggers_reserved_for_gameplay: bool = true` (default).
- En `InputProviderV2._read_live_input()`: si **no** estamos en `hud_mode`
  (`SuitOS.is_hud_mode_active() == false`) y `triggers_reserved_for_gameplay` es
  `true`, los slots de gatillo (`slot_2` = `L2`, `slot_4` = `R2`) **no** se
  publican en `d.hud_slot`.
- `L1` (`slot_1`) y `R1` (`slot_3`) siguen publicándose siempre en gameplay.
- En `hud_mode` (`is_hud_mode_active() == true`) los cuatro slots se publican
  completos para el overlay.
- `_hud_slot_is_nav_assist` solo mira el slot de `player:autonav` y respeta
  `SuitOS.shoulder_slots_suppressed`.

Constantes de índice (espejo de `SuitOS.ARK_RUN_*`): `HUD_TRIGGER_SLOTS = [2, 4]`
(números de slot 1-based = `slot_2`, `slot_4`).

## 3. Cuerda: hold vs toggle (T1 — `SpinRopeInputV2`)

- **Hold** (mando `RT` / teclado `E` / click derecho): comportamiento actual;
  `trigger_pressed` sostenido engancha y mantiene.
- **Toggle** (`touch_toggle_mode = true`, activado por la escena touch): un flanco
  de subida (`pressed and not prev_pressed`) engancha si está libre y suelta si
  está enganchada. Soltar el dedo **no** suelta.
- **Salto suelta**: si está enganchada y llega `jump_pressed` en un flanco, se
  suelta la cuerda. Nunca se escribe velocidad al soltar: el momento se conserva.
- API de `step()`: se agregan parámetros opcionales `pressed_prev`, `jump_pressed`,
  `touch_toggle` (default `false`) al final; los llamados existentes no cambian.

## 4. Dispositivo activo (T1 — `InputProviderV2`)

- `last_input_device: String` ∈ {`"keyboard"`, `"gamepad"`, `"touch"`}, actualizado
  al recibir input vivo de cada fuente; `get_active_input_device() -> String`.
- Es **presentación**, no gameplay: no viaja en `InputDataV2` ni en el replay.
  Lo consume el badge de anclaje (T4).

## 5. Touch (T2 — `MobileUI.tscn`, `MobileUIManager.gd`)

- Zonas seguras: `MoveJoystick` abajo-izquierda, `ActionButtons` abajo-derecha,
  franja superior (`y < 140` relativo al alto) reservada al HUD.
- Izquierda `IMPULSO`/`RETRAER`: espeja `thruster_boost` (mantener) + anillo Δv
  desde `spin_thruster_dv_remaining / spin_thruster_dv_max`.
- Derecha `CUERDA`/`SOLTAR`: espeja `rope_grapple` en modo toggle (ver §3).
- `AUTONAV` arriba-derecha: espeja `nav_assist`.
- Solo visibles en `SPIN_REAL` (`GravityModes.Mode.SPIN_REAL == 4`).
- Todo botón usa `TouchActionButton` (`note_touch_action` + `Input.action_press`).

## 6. HUD superior (T3 — `ArkRunTopBarView`)

- Banda `y < 140 px`. Componente `ArkRunTopBarView` reutilizado en pantalla
  completa y en la app `ship:ark_nav`.
- Barra longitudinal `[PUENTE] ══●══|══ [MOTOR]` con marcador vivo + fantasma.
- Perfil radial `HUB──TERRAZA──CASCO` (reemplaza el disco plano).
- Gravedad local con flecha a 45° cuando hay `a_axial`.
- Chips `L1` (`player:flashlight`) y `R1` (`player:autonav`).

## 7. Diegética (T4)

- Doble jet en mochila + arco segmentado Δv junto a Elías (oculto a Δv 100% en suelo).
- Retícula magnética 2D con badge del último dispositivo (`RT` / `E` / toque vía
  `get_active_input_device()`).
- Tether cian → dorado en retracción.
- `FOV +5°` con rampa mientras el propulsor está activo (término del `CameraRig`
  existente).
- Audio sutil de empuje/cuerda.

## 8. Invariantes para todas las tareas

1. Nada de input en `_process`; gameplay se lee en `_physics_process`.
2. Sin aleatoriedad en gameplay (nada de `randf()`/`randomize()`); sin
   `Engine.get_frames_drawn()` en lógica de estado.
3. Un solo `CameraRig`; nada de transiciones bruscas (AGENTS.md §1.1, §2.3).
4. `.tscn` editados por nodo (quirúrgico), nunca `pack()` del archivo completo.
5. Fuera del Ark-Run, `DEFAULT_PINS` global no cambia (solo la linterna).
6. Presupuesto de archivos por tarea (§9). Un cambio fuera de presupuesto se
   coordina aquí primero.

## 9. Presupuesto de archivos por tarea

| Tarea | Puede editar |
|-------|--------------|
| T1 | `project.godot`, `core_v2/input/InputProviderV2.gd`, `core_v2/autoloads/SuitOS.gd`, `core_v2/ui/hud/HudSlotGamepadV2.gd`, `core_v2/player/traversal/SpinRopeInputV2.gd`, `core_v2/levels/ark_run/ArkRunThrusterInput.gd`, `core_v2/tests/test_fd325_unified_input.gd` |
| T2 | `MobileUI.tscn`, `MobileUIManager.gd` |
| T3 | `ArkRunHudOverlay.gd`, `ArkNavWidget.*`, nuevo `ArkRunTopBarView.*` |
| T4 | `ArkRunAnchorVisuals.gd`, `ArkRunSlice.*`, `ArkRunLiveLoop.gd` |

Prohibidos para **todas** salvo su dueño: `WorldRotator.gd`, `CylinderRotator.gd`,
formato `.oys`.
