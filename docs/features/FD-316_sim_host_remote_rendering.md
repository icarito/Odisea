# FD-316: Sim Host Remoto — el perfil low-end-flat como render-esclavo (físicas a 60Hz en el host)

**Status:** Planned (delegada a Jules)
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-25
**Completed:** -

## Problem

El perfil **low-end-flat** (device débil, GLES2) hoy corre la simulación completa
(física Box3D + lógica) y además broadcastea telemetría — y por performance,
el broadcast fue **desactivado** (decisión 2026-09-24). Eso deja a ese device
tirando CPU de simulación + render al mismo tiempo, y sin telemetría para
sesiones con usuarios reales.

Con el **Control Remoto** (FD-294) ya existente (discovery UDP + pairing + WS),
hay una vía mucho mejor: que el **host simule** (físicas a 60 Hz, lógica, Core V2
completo) y el low-end-flat **solo renderice** el estado que recibe. El device
se convierte en un **render-esclavo** (thin client): su CPU queda casi libre,
y el host puede broadcastear telemetría por él.

## Solution

Extender el Control Remoto (FD-294) con un **canal de estado de simulación**:

- **Host** (quien tiene la sesión autoritativa, PC o device capaz): corre la sim
  completa a 60 ticks/s y **emite snapshots** del mundo (transform + animación +
  luces + cámara) a los clientes emparejados.
- **Render-esclavo** (low-end-flat): recibe snapshots, **interpola** con buffer
  de 1 tick y renderiza. **No simula nada**: sin física, sin lógica, sin Core V2.
  Su CPU queda libre; la GPU sigue siendo el único límite.
- **Input**: el control remoto ya envía `input{touch,accel,gyro}` (FD-294 F1).
  En modo render-esclavo, esos inputs se inyectan como **input virtual** con
  `tick number` — el host los aplica en el tick correspondiente. Sin segundo sim,
  **no hay desync posible**.
- **Determinismo (Core V2)**: se vuelve trivial. La autoridad es única (el host).
  Replay/checkpoints se graban igual que hoy (la fuente de input es un gamepad
  virtual). El render-esclavo no necesita ser determinista: solo interpola.
- **Telemetría**: el host la broadcastea (ya no depende del device débil).
  Para la demo con usuarios (FD-303/308 en curso), el low-end-flat deja de estar
  mudo.

### Considered Options

- **Option A — Sim local en el device + broadcast telemetría (estado actual)**: el
  device simula y renderiza; telemetría desactivada por performance.
  Pros: cero latencia de sim. Contras: CPU del device saturada, sin telemetría.
- **Option B — Sim host + render-esclavo por snapshots interpolados (elegida)**:
  Pros: CPU del device casi libre, telemetría centralizada, determinismo trivial
  (autoridad única), Core V2 intacto en el host. Contras: +1 RTT por frame de
  input; **solo viable en LAN local** (RTT bajo); GPU del device sigue siendo el
  techo real (si el bottleneck es GPU, no se gana nada).
- **Option C — Sim host + input prediction en el device**: elimina la latencia
  percibida de input, pero agrega un predictor que puede desviarse del estado
  autoritativo (requiere reconciliación). Contras: complejidad alta, no aporta
  al objetivo (60 Hz físicas + CPU libre); **backlog**.

**Alcance de esta FD**: Option B, LAN local, sin predicción de input.

## Files to Modify

Basado en `feature/FD-294-control-remoto` (ya existe la infraestructura de red:
`core_v2/net/RemoteProtocol.gd`, `RemoteControlServer.gd`, `RemoteControlClient.gd`,
`RemoteAnnouncer.gd`, `RemoteDiscovery.gd`, `RemoteControlManager.gd`):

- `core_v2/net/RemoteProtocol.gd` (modify) — mensajes nuevos: `sim_hello`,
  `sim_snapshot`, `sim_config` (tick rate, interpolación, escena base).
- `core_v2/net/RemoteSimHost.gd` (new) — autoload/manager del lado host:
  captura snapshots por tick (60 Hz), serializa, emite a clientes emparejados.
- `core_v2/net/RemoteSimClient.gd` (new) — lado render-esclavo: recibe, bufferiza
  (1 tick), interpola transforms/animación/luces/cámara, inyecta input con tick.
- `core_v2/net/RemoteControlManager.gd` (modify) — orquesta host/client según el
  rol de la sesión (rol explícito en el pairing: `host` vs `render_slave`).
- `core_v2/tests/test_remote_sim.gd` (new) — tests del protocolo y de la
  interpolación.
- `docs/features/FEATURE_INDEX.md` (modify) — entrada FD-316.

**Fuera de alcance (backlog)**: predicción de input (Option C), render-esclavo
por internet (WAN), compresión binaria de snapshots (JSON v1 alcanza en LAN;
binario solo si el perfil lo exige).

## Verification

1. **Tests automatizados** (`bin/jules-cli` corre la suite):
   - `test_remote_sim.gd` cubre: encode/decode de `sim_snapshot` y `sim_config`;
     buffer de interpolación (1 tick) sin huecos ni saltos; inyección de input
     con tick correcto; rol `render_slave` NO instancia física ni Core V2.
   - La suite existente (`test_remote_control.gd`, determinismo) sigue verde.
2. **Prueba manual en LAN (2 devices, mismo WiFi)**:
   - Host simula a 60 Hz; render-esclavo (perfil low-end-flat) renderiza
     interpola-do. Verificar FPS del esclavo >= 30 y CPU notablemente más baja
     que con sim local.
   - Input desde el esclavo: el personaje responde con lag imperceptible (<50 ms
     en LAN).
   - Telemetría: el host broadcastea y la sesión aparece con datos.
3. **Determinismo**: grabar una partida con input remoto; replay reproduce igual
   que una partida local (mismo checkpoint, mismo resultado).

## Notas de implementación para Jules

- Reusar el transporte existente de FD-294 (WebSocket para control, UDP para
  alto ritmo). Los snapshots de sim van por **UDP** (tolerante a pérdida,
  interpolación cubre huecos); el control (pairing, config) por WS.
- El render-esclavo NO toca `core_v2/` de simulación: solo un nodo receptor que
  interpola y un `RemoteTransform`-like aplicado a la escena base recibida.
- No cambiar el Core V2 ni el contrato de replay. El host sigue siendo el
  binario normal; el modo render-esclavo es un modo de arranque del mismo binario
  (export móvil ya existe, FD-294).
- La física del host corre con el fork Box3D (`godot-box3d-3`), sin cambios.
- No implementar predicción, compresión binaria ni WAN en esta FD.
