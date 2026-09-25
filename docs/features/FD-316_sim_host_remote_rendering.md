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
