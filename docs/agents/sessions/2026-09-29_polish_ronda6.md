# Polish ronda 6 — 2026-09-29

Contexto: ronda de pulido mientras se valida FD-316 (sim host + render-esclavo) en
device. Modo despachador (`iterative-list-hacking`): observaciones sueltas de Sebastián,
cada item anclado a archivos reales.

## Items

### P1 — Boot loading scene: render scale inestable al entrar al juego
El Boot loading scene varía de render scale al entrar al juego. Debería ser **constante
y legible** durante todo el boot (hoy cambia a mitad del loading y el texto se ve
distinto/ilegible en algunos frames).

Anclas:
- `core_v2/bootstrap/BootLoader.gd` — medición de arranque y elección de escala inicial.
- `core_v2/tests/test_diag_overlay_and_boot_scale.gd` — contratos existentes:
  `test_el_arranque_lento_elige_una_escala_inicial_menor` y
  `test_los_escalones_de_arranque_existen_en_la_tabla_de_escalas` (la tabla de escalones
  ya existe; el bug es la VARIACIÓN al entrar al juego, no la tabla).
- `core_v2/autoloads/SettingsManager.gd` — `apply_render_resolution()` / render_scale
  (quién re-aplica y cuándo).

Hipótesis a verificar: el escalón inicial elegido por la medición de arranque se
re-negocia cuando el juego entra (streaming del nivel, gate LOW, o el nivel pisa la
escala), en vez de fijarse UNA vez y mantenerse hasta el primer frame de gameplay.

### P2 — Pairing dialog: mouse virtual robado por Pantalla abierta + 640x480 gigante
Dos síntomas del diálogo de emparejamiento (`RemotePairingDialog.tscn`):
1. **Con el HUD en una Pantalla abierta, la pantalla se roba el mouse virtual**: el
   diálogo ya llama `VirtualMouse.attach_popup_deferred(self)` (`RemotePairingDialog.gd:18`),
   pero la Pantalla (SuitOS/hud_mode) activa le gana el manejo del puntero y el diálogo
   no es usable. El estándar de popups (AGENTS §2.3.1) espera que el popup gane.
2. **Render scale 640x480**: el diálogo se ve gigante y no centrado (el layout no maneja
   la resolución de render del lowend).

Anclas:
- `core_v2/ui/RemotePairingDialog.gd` (attach_popup + layout), `RemoteControlManager.gd:368-398`
  (montaje del diálogo sobre CanvasLayer + pausa del pairing).
- `core_v2/ui/SuitOS.gd` (Screen/hud_mode: quién captura el puntero con una pantalla abierta)
  y `core_v2/ui/VirtualMouse.gd` (`attach_popup`, prioridad popup vs screen).
- `portmaster/lowend.cfg` (640x480) + `SettingsManager.apply_render_resolution()`.

## Estado del flujo FD-316 (contexto para retomar)

- Deploy device: PCK `a3905547...` (idioma viaja con el control remoto + frame de input
  unificado + rig/arm en snapshot + resolución del player del esclavo contra el nivel).
- Peer de telemetría en desktop `:4999` (esperando que los juegos se reconecten).
- Auto-pausa por foco desactivada cuando la máquina es sim host (solo desktop, va en el
  próximo deploy).
- Pendiente el **rehearsal E2E con replay** (`user://replay_1790487798.json`,
  `buffer[i].snapshot` = oráculo por tick: posición/yaw/pitch/spring length) para medir
  dónde arranca la divergencia imagen/simulación. Local: dos instancias con
  `ODISEA_FORCE_LOW_TIER=1` + emparejamiento automatizable (el diálogo se confirma por
  telemetría: `RemoteControlManager._pairing_dialog._on_confirmed()`).
