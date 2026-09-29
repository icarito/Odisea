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

## Ensayo local por partes (2026-09-29, decisión de debugging)

Debuggear el sim host headless y el render-esclavo **juntos en device** es inviable:
dos procesos, dos hardware, y cada fix requiere rebuild+deploy. Plan: ensayar cada mitad
por separado, localmente, y usar el banco in-process como contrato de coherencia.

**Banco in-process** (`test_remote_sim.gd > test_local_rehearsal_pipeline_matches_authority`):
host y esclavo en el mismo árbol. Verifica (1) que el input del control (acciones del
`Input` real vía provider) y el del handheld (`sim_input`) terminen en **un** frame
inyectado a la autoridad, y (2) que el esclavo reproduzca player + rig + `arm_len` +
cámara exactamente lo que la autoridad capturó. Descubrió un bug real: el snapshot se
aplicaba contra `SessionManager.player`, que el autoload pisa a null fuera de
`current_scene` — ahora el rig/cámara se resuelven contra el nivel del esclavo
(`RemoteSimClient._get_scene_player`), igual que el loop de entidades.

**Ensayo con replay real** (`user://replay_1790487798.json`): el replay ya trae el
lenguaje completo por tick:
- `buffer[i].frame.input` → el `InputDataV2` de ese tick (entrada para la autoridad).
- `buffer[i].snapshot` → posición/velocity/**yaw/pitch/base_spring_length_3d**/estados
  (el estado esperado del player Y su rig de cámara, tick por tick).
- `meta.world_start_state` + `meta.scene` → arranque; `final_expected_state` → oráculo.
- `events` → OYS por tick (en esta grabación, la secuencia de despertar con
  `open_pod_hatch`).

Rehearsal A (autoridad, ya existe como base): el determinismo del Core con ese replay
(`test_determinism_v2`) valida input → estado. Falta agregar: correrlo a través del
pipeline del sim host (`_apply_authority_input_frame`) y comparar cada snapshot contra
`buffer[i].snapshot` (posición/yaw/pitch/arm).

Rehearsal B (esclavo): sintetizar snapshots desde `buffer[i].snapshot` (root + rig
yaw/pitch + `base_spring_length_3d`) y verificar que el esclavo reproduzca rig/arm/
cámara — sin device y sin simular.

**Cuestión abierta de diseño** (la que motiva esto): hoy el esclavo recibe la cámara
final forzada (`cam_t`) + el rig replicado. La meta declarada por Sebastián es que la
vista salga del **input** también: si el frame de input es completo y determinista, el
rig de cámara debería poder reconstruirse en el esclavo desde el input + el estado
replicado, y `cam_t` quedar como verificación (o eliminarse). El replay es el oráculo
para decidir si eso es posible sin simular el mundo.

## Fixes de la prueba en campo (2026-09-28, Kilo)

Reportes de Sebastián con el Anbernic como render-esclavo y el desktop como control:
no se veía el mesh/animación del Player, y al cambiar de ventana en el desktop volvía a
sonar la apertura del pod.

1. **Player ausente del snapshot** (`RemoteSimHost.capture_snapshot`). El Pilot real no
   pertenece a `replay_sync` (solo sus hijos `ControllerManager`/`MultiTool`), así que el
   grupo nunca quedaba vacío y el fallback viejo al grupo `player` no disparaba: el
   jugador no viajaba y su mesh quedaba en el spawn mientras la cámara seguía a la
   autoridad. Ahora el/los jugadores del nivel simulado se agregan siempre a las
   entidades, además de los `replay_sync`.
2. **Animator congelado** (`PlayerControllerV2.step_remote_animator` +
   `RemoteSimClient._process`). Con el `_physics_process` del Pilot congelado nadie
   llamaba `step_animator`; el AnimationTree quedaba en la pose de spawn. El cliente lo
   alimenta a mano con la velocidad que llega en el snapshot.
3. **Recarga del nivel al perder foco** (`RemoteSimHost.start_simulation`/
   `load_sim_level`/`stop_simulation`, `RemoteControlManager`). Una reconexión
   transitoria (perder foco → pausa → reconectar) re-enviaba `start_sim_host` +
   `sim_hello` y el nivel se recargaba: su `_ready` volvía a correr la intro de despertar
   (el pod sonaba de nuevo). Ahora:
   - `load_sim_level` es idempotente: si el mismo nivel ya está montado y listo, se
     conserva y solo se re-sincroniza la pose del handheld.
   - `start_simulation` conserva el nivel montado y no resetea el tick (si no, quedaría
     por detrás del último aplicado y el esclavo descartaría todo).
   - `connection_lost` hace stop **blando** (conserva el nivel); `session_ended` sigue
     descargándolo.
4. **Look de cámara y unificación del input** (`RemoteSimHost._apply_authority_input_frame`).
   Antes la autoridad procesaba el input por dos caminos distintos: el control lo leía su
   `InputProviderV2` y el handheld se materializaba como acciones globales con
   `Input.action_press` (que ensuciaba el input de la máquina del control y no admitía el
   look, porque no es una acción del `InputMap`). Ahora, una vez por tick, la autoridad arma
   **un `InputDataV2`** con el input local del control (provider, ya con curvas/gate) +
   `axes`/`buttons` del handheld + el look de ambos (`mouse_delta`/`zoom_delta`) y lo inyecta
   con `player.inject_input()`. Se eliminó el `action_press` global.
   Además, como render-esclavo ya no se aplican los `event` del control a su `Input`
   (`RemoteControlManager._on_server_input_received`): eso se reenviaba por `sim_input` y
   la autoridad lo recibía dos veces (local + eco).
5. **La cámara del handheld la procesa su propio `InputProvider`** (`RemoteSimClient`).
   Antes se mandaba el look en crudo, así que el **D-pad** (cámara digital del provider,
   con rampa y curva) no llegaba nunca: no es una acción del `InputMap`. Ahora el
   handheld llama `provider.get_input()` (una vez por frame, el player está congelado) y
   manda el `mouse_delta`/`zoom_delta` ya procesado; la autoridad lo suma tal cual. El
   touch que reenvía el control entra al mismo provider vía `add_touch_camera_drag`.
6. **Rig completo en el snapshot** (`RemoteSimHost._capture_player_rig` /
   `RemoteSimClient._apply_player_rig`). Además de `cam_t`, viaja la cadena
   `CameraRig/Yaw/Pitch/OTS_Offset/SpringArm` y el `current_length` del kinematic arm:
   sin eso el esclavo quedaba con el rig en la pose de spawn aunque la vista se forzara
   por `cam_t`.

> Se probó **suprimir** la intro de despertar en el nivel montado, pero el pod quedaba
> cerrado: esa intro es el único camino que abre la escotilla. Revertido; la repetición
> del sonido la evita la carga idempotente de arriba.

Tests nuevos en `core_v2/tests/test_remote_sim.gd` (20 casos, 0 fallos): jugador fuera de
`replay_sync` presente en el snapshot; `sim_hello` repetido con la misma escena no recarga;
`step_remote_animator` sin animator no explota; el look del cliente viaja en el frame
inyectado; el frame fusiona ejes/botones sin tocar el `Input` global. Correr:
`./.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_remote_sim or test_remote_control or interaction_prompt_clear"`.

**Qué probar en device** (reiniciando el juego del desktop, que es el control): el mesh y
la animación del Pilot se ven y siguen a la cámara; al cambiar de ventana en el desktop
ya no vuelve a sonar la apertura del pod; girar la cámara (mouse del desktop o stick del
Anbernic) mueve la vista.

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
