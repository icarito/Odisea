# Sesión: Pulido controles vertical slice — esquema unificado del Multi-tool (2026-11-14)

Estado: EN PROGRESO (worker src-50).

## Objetivo
Unificar el esquema de control del multi-tool entre mouse/teclado, gamepad y touch, y volver la
herramienta diegética (objeto equipable del HUD, patrón FD-298 / Linterna).

## Decisiones de Sebastián (cerradas)
1. Láser y gloo NO son "modos" que se ciclan: son objetos/vistas equipables del HUD con su propia
   pantalla (patrón Linterna: widget + screen + acciones). Se seleccionan/equipan desde el HUD
   (o los slots de hombro). Un solo botón de uso dispara el tool equipado.
2. Se elimina el modo GRAB del Multi-tool (empujar sigue vía PushableBoxV2).
3. Crosshair visible solo con tool equipado (láser o gloo), minimalista, sin texto.
4. El multi-tool debe quedar bien ubicado en la mano del piloto.

## Conflictos anclados
- C1: rueda = zoom_in/zoom_out Y tool_next/prev_mode a la vez → se quitan las acciones
  `tool_next_mode`/`tool_prev_mode` del [input]; la rueda queda SOLO zoom.
- C2: clic izquierdo = tool_fire_primary E interact → interact gana si hay interactuable apuntado/
  en prompt; si no, dispara. Resolución en InputProviderV2 (archivo permitido), consultando el
  target actual del jugador (`_current_interactable`).
- C3: gamepad sin tool_fire_primary → se asigna disparo al gatillo derecho (botón 7, RT). El
  botón 7 deja de ser slot_4. La cruceta deja de ciclar modos (las acciones de ciclo desaparecen).
- C4: botones touch de tiro/cambio (commit 87ed7d56) → 1:1 con el mapa del gamepad: FireButton =
  RT (tiro); ToolPrev/ToolNext pasan a ser slots de hombro (slot_2/slot_3), que equipan láser/
  gloo. Tap sobre slot vacío abre el radial para elegir qué fijar.

## Mapa de control final

| Acción | Mouse/Teclado | Gamepad | Touch |
|---|---|---|---|
| move / look | WASD + mouse | sticks | joystick virtual + drag |
| interact | E; LMB comparte con tiro (gana interact) | X (botón 2) | InteractButton |
| tool_fire_primary (uso tool equipado) | LMB (suprimido si interact ganó) | RT (botón 7, NUEVO) | FireButton "TIRO" |
| tool_fire_secondary | — | — | — |
| zoom | rueda (solo zoom) | — | pellizco |
| slot_1 | tecla 1 | LB (4) | — (HUD) |
| slot_2 | tecla 2 | LT (6) | ToolPrevButton "LASER" |
| slot_3 | tecla 3 | RB (5) | ToolNextButton "GLOO" |
| slot_4 | tecla 4 | (sin pad, se libera RT) | — (HUD) |
| hud_mode | TAB | Y (3) | HUDButton |
| cargol_ability | G / MMB | — | — |
| toggle_flashlight | L | tap LB (slot_1) | — |
| jump | Espacio | B (1) | JumpButton |
| crouch | C | A (0) | CrouchButton |
| run | Shift | stick analógico | auto-sprint |
| pausa pasiva | START (pad) / Esc | START | — |
| liberar/recapturar mouse | MMB | SELECT (10) | — |

Convenciones que se conservan: START=pausa pasiva, SELECT=liberar/recapturar mouse, Jump(B)=back,
determinismo (física en _physics_process; InputDataV2 serializable; from_dict tolerante a replays
viejos con tool_next/prev_mode).

## Archivos que se tocan
- project.godot (solo [input])
- core_v2/input/InputDataV2.gd, InputProviderV2.gd
- core_v2/player/MultiToolV2.gd, MultiToolModeIndicator.gd (se conservan stubs no-op de
  get_grabbed_body/release_grab para no tocar core_v2/props/machines/MachineLevel.gd [prohibido])
- core_v2/player/PlayerControllerV2.gd (solo transform de mano + crosshair)
- core_v2/ui/hud/* (MultiToolWidget, HudSlotGamepadV2, nuevos LaserScreen/GlooScreen/LaserWidget/
  GlooWidget)
- core_v2/ui/MobileUI.tscn
- tests relacionados: test_touch_multitool_controls.gd, test_remote_control_touch_multitool.gd,
  test_multitool_gloo.gd, test_multitool_screen.gd, test_machine_level.gd (test GRAB), mobileui.oys
- docs/agents/sessions/2026-11-14_polish_controles.md (este doc)

Prohibido: core_v2/props/machines/*, core_v2/levels/machines/* (otro worker). No revertir cambios
ajenos. Commits locales sí. Push/PR al final (autorización de src-49).

## Rehacer del crosshair (feedback de Sebastián sobre 2e9ada1c)
- El retículo fijo en el centro no servía por paralaje OTS: el tool dispara desde la mano.
- Nuevo `core_v2/ui/hud/MultiToolCrosshair.gd` (fuera de PlayerControllerV2):
  - Láser: retículo proyectado con `camera.unproject_position` sobre el MISMO rayo del
    disparo (muzzle del MultiToolLaser, `-basis.z`, `laser_max_range`,
    `laser_collision_mask`).
  - Gloo: predice el arco balístico (`gloo_projectile_speed`, `gloo_projectile_gravity`,
    igual que MultiToolGlooProjectile) y marca el punto de aterrizaje.
  - Estados sin texto: forma = tipo de tool (láser: cruz; gloo: rombo + núcleo),
    color = válido/fuera de rango/obstruido/interactuable apuntado (gana el clic, C2),
    pulso al disparar, brillo con el calor del láser, núcleo = cooldown del gloo.
  - Suavizado exponencial de posición; tier LOW recalcula a mitad de frecuencia.
- PlayerControllerV2 solo instancia el nodo (el resto vive en el script nuevo).
- Validación: capturas centro/izquierda/derecha/cercano (<2000 px) en
  `~/.ao/data/artifacts/src-50/crosshair_*2.png`; test `test_multitool_crosshair.gd`
  verifica que el punto proyectado coincide con el impacto real del rayo (caso central y
  lateral).

## Seguimiento (feedback de Sebastián sobre las capturas)
1. **Texto de modo eliminado**: se quitaron los nodos `HUD/UIIndicator` (`ModeLabel`,
   `CountLabel`) de `MultiToolV2.tscn` y su llamada en `step()`; `MultiToolModeIndicator.gd`
   quedó sin uso y se eliminó. El estado del tool ya no se pinta como texto; lo muestran las
   pantallas HUDable (Láser/Gloo).
2. **Crosshair dinámico y caso obstruido visible**: se agregó punto central del láser, anillo
   rojo pulsante cuando el objetivo está obstruido, y un heurístico de obstrucción sin falsos
   positivos (algo pegado al arma, o el centro de pantalla mira al vacío mientras el muzzle golpea
   algo cercano). La proyección ya no oculta el retículo con un punto muy cercano: lo sujeta al
   borde del viewport.
3. **Tool en la mano**: el multi-tool ahora cuelga de un `MultiToolGrip` montado en un
   `BoneAttachment` del hueso `DEF-handR` (sigue la animación). El grip es el pivote que apunta al
   objetivo; el tool conserva una pose local de agarre (solo roll + offset de palma, para no torcer
   el eje de disparo -Z). Si no hay hueso, cae a un socket fallback.
4. **Review PR #411**: C2 ahora solo cede el clic COMPARTIDO (botón izquierdo) ante interact, sin
   cancelar controles independientes (E/gamepad/touch); el tap de slot alterna el estado cuando no
   se pasa `desired` (Láser/Gloo).

Capturas finales (`~/.ao/data/artifacts/src-50/`): `crosshair_laser_valid.png`,
`crosshair_laser_izquierda.png`, `crosshair_laser_derecha.png`, `crosshair_laser_obstruido.png`,
`crosshair_gloo_lado.png` (800x450, jugador en cuadro para ver la mano).

## Seguimiento 2 — PR apilado (mano en la palma + paridad del gloo + hitbox táctil)
Tras mergear #411 (65d848e8), se abre un PR de seguimiento directo a main:
1. **Tool en la palma**: el modelo del multi-tool trae su geometría desplazada (Model en
   `(0.2,-0.2,-0.3)`, Laser/GlooSpawnPoint en `(0.2,-0.2,-0.5)`), por lo que flotaba al costado. En
   `_apply_multi_tool_hand_transform` se cancela ese offset: `origin = (-0.2, 0.2, 0.3)` (Model en
   el origen del grip; muzzle 0.2 m al frente) y solo un roll leve. Verificado: el Model queda a
   ~6 cm del hueso `DEF-handR`.
2. **Paridad del arco del gloo (review P2 de #411)**: se factorizó el paso balístico del
   proyectil en `MultiToolGlooProjectile.step_ballistic` (gravedad ANTES de avanzar + radio de
   colisión); `step()` y `MultiToolCrosshair._refresh_gloo_target` lo reutilizan. El retículo ahora
   consulta una **esfera** (`intersect_shape`) en el extremo de cada paso, igual que el
   `move_and_collide` del proyectil, para no errar obstáculos de borde. Test de paridad
   `test_multitool_gloo_parity.gd` (obstáculo de borde; distancia medida ~0.07 m).
3. **Hitbox táctil a escala (mismo fix de #414)**: `PlayerControllerV2._is_over_touch_control` y
   `ElevatorFloorSelector._is_over_touch_control` usan `UIScaleCompensator.point_in_control` en vez
   de `get_global_rect().has_point()` (que no escala el tamaño). Caso nuevo en
   `test_touch_hitbox_scale.gd`.

Capturas (Viewport hijo in-process, 800x450, cámara cerca de la mano):
`~/.ao/data/artifacts/src-50/hand_laser.png`, `hand_gloo.png`.

## Pasos
1. project.godot [input]: quitar tool_next_mode/tool_prev_mode; agregar botón 7 a
   tool_fire_primary; quitar botón 7 de slot_4.
2. InputDataV2.gd: quitar campos tool_next/prev_mode (to_dict/is_equal_to); from_dict tolerante.
3. InputProviderV2.gd: dejar de leer tool_next/prev; lógica C2 (interact gana).
4. MultiToolV2.gd: enum Equipped {NONE, LASER, GLOO}; quitar GRAB; set_equipped(); step() por
   equipado; snapshot/restore tolerante; stubs no-op para MachineLevel.
5. MultiToolModeIndicator.gd: mostrar equipado + count de gloo (sin GRAB).
6. Nuevos screen/widget en hud/: LaserScreen, GlooScreen, LaserWidget, GlooWidget (.gd/.tscn);
   MultiToolV2 los instancia en _ready (grupo "multitool").
7. HudSlotGamepadV2.gd: tap sobre slot vacío abre radial (equip en 2 taps).
8. MobileUI.tscn: ToolPrev → slot_2 "LASER", ToolNext → slot_3 "GLOO"; FireButton intacto.
9. PlayerControllerV2.gd: CanvasLayer Crosshair (centrado, minimalista, sin texto) visible solo con
   tool equipado; ajuste fino del transform de mano.
10. Tests puntuales (pytest -k multitool/input/hud) y capturas (crosshair + mano, <2000px).
11. ao report; rebase sobre origin/main, push, PR a main (coordina merge src-49).
