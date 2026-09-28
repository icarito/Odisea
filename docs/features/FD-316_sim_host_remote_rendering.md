# FD-316: CPU offload al control remoto — render-esclavo para host low-end-flat

**Status:** Planned (delegada a Jules)
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-25
**Completed:** -

## Objetivos

1. **Liberar CPU** en devices muy débiles (perfil `low-end-flat`, GLES2): el device
   apaga su propia simulación de física y solo renderiza.
2. **Stress-testear el engine**: ejercitar el fork Box3D + Core V2 con la simulación
   corriendo a 60 Hz bajo input local, validando determinismo y replay en una
   topología invertida (control remoto simula headless, host débil renderiza).

**No es objetivo**: subir FPS. El RG351V ya está limitado por draws/driver, no por
el tick (medido en `c9bc04bf`: proc/tick 30→28 ms, phys/tick 35→30 ms, FPS sin
cambio). Esto libera CPU, no mueve el FPS de un device draw-bound.

## Problem

El perfil `low-end-flat` corre la simulación completa (física Box3D + lógica) y
además renderiza — su CPU queda saturada, y por eso el broadcast del control
remoto fue desactivado en tier LOW (`c9bc04bf`).

## Solution — CPU offload invertido, SOLO para host débil

El **caso de uso es uno y solo uno**:

> Cuando el **host** de la sesión es un device **low-end-flat**, el pairing de
> control remoto gatilla que **el device control remoto** (el teléfono, más
> potente) corra la simulación **sin mostrarla** (headless), y le transmita al
> host low-end el estado de la escena para que este renderice **únicamente** la
> parte gráfica con su propia simulación de física **apagada**.

Detalle del flujo (control remoto = teléfono emparejado vía FD-294):

1. **Gatillo**: pairing de control remoto establecido Y host en tier LOW. En
   cualquier otra combinación (host capaz, o cualquier cliente), el control
   remoto funciona **exactamente como hoy** — este camino no lo toca.
2. **Control remoto → simulador headless**: corre física (Box3D, 60 Hz) + lógica
   + Core V2 completos, pero **sin renderizar** la escena. Procesa los inputs
   **localmente** (el input nace en el propio teléfono, así que no hay RTT de
   input). Es la **autoridad única**.
3. **Control remoto → host low-end**: transmite el **estado de la escena**
   (snapshots por tick: transforms, animación, luces, cámara) por el transporte
   de FD-294 (UDP para snapshots de alto ritmo, WS para control/pairing).
4. **Host low-end → render-esclavo**: recibe snapshots, interpola (buffer de 1
   tick) y renderiza solo lo gráfico. Su simulación de física está **apagada**
   (no instancia física ni Core V2); su CPU queda libre para el render.
5. **Determinismo (Core V2)**: trivial — una sola autoridad (el control remoto).
   Replay/checkpoints se graban en el control remoto, igual que hoy (el input es
   el gamepad/touch virtual local). El render-esclavo no necesita ser
   determinista: solo interpola.

### Considered Options

- **Option A — Sim local en el host débil (estado actual)**: el host simula y
  renderiza; broadcast desactivado por performance. Contras: CPU saturada, sin
  margen para telemetría.
- **Option B — CPU offload al control remoto (elegida)**: el control remoto
  simula headless y el host débil solo renderiza. Pros: CPU del host casi libre,
  determinismo trivial (autoridad única), sin RTT de input (el input se procesa
  en el propio control remoto). Contras: solo aplica cuando el host es débil;
  GPU del host sigue siendo el techo (si es draw-bound no sube FPS); LAN local
  (RTT de snapshots).
- **Option C — Sim host + predicción de input en el device**: no aplica aquí
  (el input se procesa localmente en el control remoto, no hay que predecirlo).
  Queda **backlog**.

**Alcance de esta FD**: Option B, LAN local, solo para el caso host = low-end-flat.

## Off limits

- **El sistema de control remoto como funciona hoy para el resto de
  combinaciones** (host capaz + control remoto, cualquier cliente). No se cambia
  su comportamiento, pairing, UI ni protocolo para esos casos.
- Core V2 / replay / determinismo: no se altera el contrato. El control remoto
  sigue siendo el binario normal; el modo headless-sim es un modo de arranque del
  mismo binario.
- Predicción de input, compresión binaria de snapshots, WAN: **backlog**.

## Files to Modify

Basado en `feature/FD-294-control-remoto` (infraestructura de red ya existe:
`core_v2/net/RemoteProtocol.gd`, `RemoteControlServer.gd`, `RemoteControlClient.gd`,
`RemoteAnnouncer.gd`, `RemoteDiscovery.gd`, `RemoteControlManager.gd`):

- `core_v2/net/RemoteProtocol.gd` (modify) — mensajes nuevos: `sim_hello`,
  `sim_snapshot`, `sim_config` (tick rate, interpolación, escena base).
- `core_v2/net/RemoteSimHost.gd` (new) — lado **control remoto**: simulación
  headless (Box3D + Core V2) a 60 Hz, captura y emite snapshots por tick.
- `core_v2/net/RemoteSimClient.gd` (new) — lado **host low-end**: recibe
  snapshots, bufferiza (1 tick), interpola transforms/animación/luces/cámara y
  renderiza; **desactiva** la simulación local de física.
- `core_v2/net/RemoteControlManager.gd` (modify) — detecta el gatillo
  (host = tier LOW + pairing activo) y asigna roles `sim_host` (control remoto) /
  `render_slave` (host low-end) sin tocar el flujo normal de los demás casos.
- `core_v2/tests/test_remote_sim.gd` (new) — tests del protocolo y de la
  interpolación.
- `docs/features/FEATURE_INDEX.md` (modify) — entrada FD-316.

**Fuera de alcance (backlog)**: predicción, WAN, compresión binaria (JSON v1
alcanza en LAN).

## Verification

1. **Tests automatizados** (`bin/jules-cli` corre la suite):
   - `test_remote_sim.gd` cubre: encode/decode de `sim_snapshot` y `sim_config`;
     buffer de interpolación (1 tick) sin huecos ni saltos; rol `render_slave`
     NO instancia física ni Core V2; el gatillo solo se activa con host en tier
     LOW (el resto de combinaciones siguen el flujo normal).
   - La suite existente (`test_remote_control.gd`, determinismo) sigue verde.
2. **Prueba manual en LAN (host low-end-flat + control remoto)**:
   - El control remoto simula a 60 Hz headless; el host low-end renderiza
     interpolado. Verificar CPU del host notablemente más baja que con sim local.
   - Input desde el control remoto: el personaje responde sin lag perceptible
     (el input se procesa localmente en el control remoto).
   - Verificar que con un **host capaz** el control remoto sigue funcionando
     igual que antes (regresión del caso normal).
3. **Determinismo**: grabar una partida con input del control remoto; replay
   reproduce igual que una partida local (mismo checkpoint, mismo resultado).
4. **Stress-test del engine (objetivo principal)**: correr el control remoto con
   simulación a 60 Hz headless bajo input sostenido y medir: tick rate estable
   (sin hitches), determinismo de replay bajo carga, y CPU del host. Ejercitar
   el fork Box3D + Core V2 en topología invertida y reportar dónde se rompe
   primero (física, serialización de snapshots, red). El resultado es un informe,
   no solo verde/rojo.

## Estado real y reparto de roles (2026-09-28, Sebastián)

**Qué hay en main** (`e3b6da8f`, `66bb2b6d`, `0d4d837c`, `53fc3c19`): emparejamiento y roles
(`RemoteControlManager.update_offload_roles`), canal UDP de snapshots, interpolación en el
render-esclavo (`RemoteSimClient`), interacción autoritativa, input del esclavo aplicado en la
autoridad, mute del esclavo. **Falta la pieza central**: `RemoteSimHost.start_simulation()` no
carga ningún nivel; captura lo que el control tenga abierto (`RemoteControlHome`, sin jugador). El
mensaje `sim_hello` (`RemoteProtocol.create_sim_hello(scene_path, …)`) existe pero nadie lo manda
ni lo consume. Por eso la promoción a render-esclavo está apagada
(`RemoteControlManager.RENDER_SLAVE_OFFLOAD_READY = false`).

**Reparto decidido:**

| | Control remoto (sim host) | Handheld low-end (render-esclavo) |
|---|---|---|
| Nivel | cargado, **sin render** | cargado, solo como escena visual |
| Física / lógica / interacción | **sí** (autoridad) | no (física apagada) |
| Audio (música + SFX) | **sí**, se escucha en el control | no (bus Master muteado) |
| Render | no (su pantalla sigue siendo la UI del control remoto) | sí, aplicando los snapshots |
| Input | local del control + el del handheld por UDP | se envía a la autoridad |
| HUD / widget de contexto | lo resuelve la autoridad; el bridge lo muestra en ambos | lo pinta desde el snapshot |

**Lo que hay que construir:**
1. Handshake: al promover, el esclavo manda `sim_hello` con escena, estado de spawn (posición,
   yaw, checkpoint, `run_seed` de SessionManager) y config de tick.
2. El sim host carga ese nivel **sin reemplazar** la UI del control (`RemoteControlHome` sigue
   como pantalla). Decidir con evidencia: nivel en un `Viewport` propio con
   `render_target_update_mode = UPDATE_DISABLED` + `own_world` (y listener 3D habilitado para
   que suene el audio), vs. cambiar `current_scene` y mantener la UI en un CanvasLayer. Tener en
   cuenta que `SessionManager.player`, `SceneManager` y los autoloads asumen `current_scene`.
3. El sim host arranca a emitir snapshots **recién** cuando el nivel está listo y tiene jugador
   (`sim_ready`); el esclavo apaga física y audio **al recibir el primer snapshot válido**, no al
   promover.
4. Salida limpia: al desemparejar, el sim host descarga el nivel y el esclavo retoma su
   simulación local desde el último snapshot (sin teletransporte).
5. Recién entonces `RENDER_SLAVE_OFFLOAD_READY = true`.

### Decisión de implementación (paso 2, 2026-09-28)

**Elegido: nivel en un `Viewport` hijo del `RemoteSimHost` con
`render_target_update_mode = UPDATE_DISABLED`, compartiendo el mundo principal (sin
`own_world`), con `audio_listener_enable_3d = true` y rutas de snapshot relativas al
nivel simulado.** La UI del control (`RemoteControlHome`) sigue siendo `current_scene`
en el teléfono.

Evidencia que descarta cambiar `current_scene` (Option B del contrato):

- `RemoteControlHome` es la `current_scene` del control y la monta `change_scene()`
  (`core_v2/ui/Menu.gd:248`, `core_v2/ui/RemoteControlMenu.gd:217`). Ahí vive el
  gamepad del sim host: `_send_touch_actions` lee las acciones del Input local y las
  reenvía, y `HudSlotGamepadV2`/`RemoteHudBackend` montan el HUD encima. Cambiar de
  escena la liberaría (el sim host se quedaría sin su propio mando); re-parentarla a
  un CanvasLayer es cirugía de UI fuera de alcance.
- `RemoteControlManager._sync_host_for_scene` decide hostear según
  `current_scene.filename`: con el nivel como `current_scene`, el teléfono levantaría
  announcer/server y se anunciaría como host mientras es cliente del handheld
  (topología invertida rota, y el off-limits prohíbe tocar ese flujo).
- `SessionManager._find_player()` corre cada tick de física y pisa `player = null`
  cuando el jugador no está bajo `current_scene` (`_is_player_candidate_valid`).
  Confirmado: los autoloads asumen `current_scene`. Con el viewport oculto el sim
  host no pelea contra el autoload: `RemoteSimHost` mantiene sus propias referencias
  (`_sim_level`, `_sim_player`) y el spawn lo resuelve el mismo camino que un F6
  (`SceneManager._ensure_player_in_current_scene`, sin modificar el autoload).
- `RemoteControlManager.update_offload_roles` solo promueve en escena de gameplay;
  con `current_scene` intacto ese chequeo y el de pausa (`PauseManager`) siguen
  comportándose igual en el teléfono.

Por qué compartir mundo en vez de `own_world`: un segundo `World` crearía un segundo
espacio de física cuyo stepping no es verificable desde GDScript (la propia sonda
`split_load_frame` de `SceneManager` apaga el `PhysicsServer` global para afectar a
todo). `UPDATE_DISABLED` ya cuesta cero GPU y en el viewport raíz del control no hay
cámara 3D (`Camera.current` es por-viewport), así que nada dibuja el mundo compartido.
El audio posicional sale del listener propio del viewport; la BGM del nivel entra por
`AudioManager` normal (el contrato pide que el control suene).

Consecuencias aceptadas: el nivel del sim host no pasa por `SceneManager.goto_scene`
(su spawn/estado lo aplica `RemoteSimHost` desde `sim_hello`: `restore_snapshot` del
controlador + `run_seed` fijado ANTES de instanciar); los scripts del nivel que lean
`current_scene` dentro del viewport oculto resolverán a `RemoteControlHome`. La
salida limpia es simétrica: `stop_simulation()` descarga el nivel, y el cliente del
control detiene el sim host si la sesión WS se cae (`connection_lost`/`session_end`).

## Notas de implementación para Jules

- Reusar el transporte existente de FD-294. Snapshots de sim por **UDP**
  (tolerante a pérdida, la interpolación cubre huecos); control (pairing/config)
  por WS.
- El render-esclavo NO toca `core_v2/` de simulación: solo un nodo receptor que
  interpola y aplica transforms a la escena base recibida.
- El control remoto simula headless con el mismo binario; no se recompila el
  fork ni se cambia Box3D.
- No implementar predicción, compresión binaria ni WAN en esta FD.
- **Cuidado con el off limits**: el gatillo solo debe activarse cuando el host es
  tier LOW. No alterar el comportamiento del control remoto en los demás casos.
