# FD-294: Control Remoto — compañero telefónico para sesiones de ODISEA

**Status:** In Progress (delegada a Jules)
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-10
**Completed:** -

## Problem

Jugar en PC y querer controlar sistemas de la nave desde el teléfono.
DroidPad descartado: limitado y sin reuso del estilo visual del juego. La
sesión principal de ODISEA debe poder **anunciarse en la red**, **emparejarse**
con el teléfono y enviarle contenido (UI, y más adelante mapas/cámaras 3D)
mientras recibe input (touch, acelerómetro, giroscopio).

## Solution

Mismo binario en ambos lados (export móvil ya existe). Item de menú
**CONTROL REMOTO** presente en todas las builds.

### Experiencia canónica (decidida con Sebastián)

1. Menú principal → **CONTROL REMOTO**. Diálogo explicativo: "Aquí aparecen
   las sesiones de ODISEA en curso en tu red local. Selecciona una y pulsa
   Emparejar para controlarla desde este dispositivo."
2. **Descubrimiento**: cada sesión de ODISEA en marcha se anuncia por
   **UDP broadcast** (~cada 2 s) con JSON:
   `{app:"odisea", session_name, version, ws_port, proto:1}`.
   mDNS/zeroconf queda como mejora posterior (Godot 3 no trae zeroconf
   nativo; UDP broadcast es portable y suficiente en LAN).
3. La pantalla CONTROL REMOTO lista sesiones vivas (nombre, versión, edad
   del último anuncio) y ofrece **EMPAIRAR**.
4. **Pairing**: gatilla un diálogo de confirmación en la sesión viva
   ("¿Permitir control remoto desde <dispositivo>?") con PIN de 6 dígitos
   visible en ambos lados. Aceptar → token de sesión y canal abierto.
   Rechazar/timeout (30 s) → volver a la lista.
5. Emparejado: la sesión principal envía directivas y el teléfono muestra
   escenas — **F1: paneles/mensajes/decisiones UI**; F2: espejo de
   HoloTerminals, mapas, vistas de cámara 3D. El teléfono envía input:
   touch (pointer) y **sensores**.

### Transporte

- **Control channel: WebSocket** (TCP fiable y ordenado; WebSocketServer
  existe en Godot 3) — pairing, directivas, input discreto.
- **Stream de sensores: UDP** (alto ritmo, tolerante a pérdida) reutilizando
  el patrón probado del addon `remote_skeleton_udp` (PacketPeerUDP +
  `heartbeat_timeout` + smoothing).
- Formato JSON v1; binario solo si el perfil de rendimiento lo exige.

### Protocolo v1 (mensajes)

- `announce` (UDP, host→red) / `discover_request`+`discover_reply` (opcional)
- `pair_request{pin, device_name}` / `pair_result{ok, token|reason}` (WS)
- `input{type:"touch"|"accel"|"gyro", payload}` (teléfono→host)
- `ui{op:"message"|"prompt"|"clear", payload}` (host→teléfono, F1)
- `scene_directive{kind:"ui"|"map"|"camera", payload}` — reservado F2
- `ping`/`pong` + heartbeat para estado "Reconectando…"

### Extensión natural: sensores del teléfono como input

El giroscopio/acelerómetro son solo otro mensaje `input{}` del protocolo:
Godot 3 expone `Input.get_accelerometer()` / `get_gyroscope()` en móvil.
El costo real es UX (dead zones, calibración, opción de apagar), no infra.
Casos de uso candidatos: pilotar con orientación, apuntado Multi-tool,
mirar alrededor en paneles. Gameplay-sensor entra en F2+; el transporte
existe desde F1.

### Alcance delegado (fases)

- **F1 (este encargo a Jules)**: announcer host + listener cliente; menú
  CONTROL REMOTO con diálogo + lista de sesiones; flujo de emparejamiento
  con confirmación y PIN en el host; WebSocket con token; `ui{message,prompt}`
  host→teléfono; `input{touch,accel,gyro}` teléfono→host (echo/log en host).
  Setting "Control remoto: ON/OFF". Sin emparejar → cero overhead.
- **F2 (después, otra sesión)**: espejo real de HoloTerminals (serializar
  TerminalUI), mapas, cámaras 3D, consumo gameplay de sensores.

### Considered Options

- **Option A: DroidPad** — descartado: UIs ajenas al juego, mapeo manual.
- **Option B: Protocolo propio WS+UDP con reuso de HoloTerminals (seleccionada)** —
  look consistente, control total, reusa prework; cuesta protocolo propio.
- **Option C: Segunda instancia en modo panel** — descartada: sincronizar el
  mundo completo cuesta más que espejar UI.
- **Option D: mDNS/Zeroconf para discovery** — diferido: sin soporte nativo
  en Godot 3; UDP broadcast cumple el requisito.

### Prework existente (no reinventar)

- `addons/remote_skeleton_udp/` en `origin/feat/add-remote-skeleton-udp-7371052930552480670`
  (commit `5affad4f`): receptor UDP/JSON con heartbeat, lerp smoothing,
  auto-start — **patrón directo para el stream de sensores**. Traer el addon
  a main como referencia o base.
- `origin/feat/remote-skeleton-udp-exp`: variante exp con
  `scripts/multiplayer/LocalMultiplayerManager.gd` (344 líneas) y
  `PlayerInput.gd` — referencia de input remoto/jugadores locales.

## Files to Modify

- `core_v2/net/RemoteAnnouncer.gd` (nuevo — UDP broadcast del host)
- `core_v2/net/RemoteDiscovery.gd` (nuevo — listener de anuncios, cliente)
- `core_v2/net/RemoteControlServer.gd` (nuevo — WebSocketServer + pairing + token)
- `core_v2/net/RemoteControlClient.gd` (nuevo — cliente del teléfono)
- `core_v2/net/RemoteProtocol.gd` (nuevo — mensajes JSON v1, serialize/parse)
- `core_v2/ui/Menu.gd` (item CONTROL REMOTO: diálogo, lista, emparejar)
- `core_v2/ui/RemotePairingDialog.gd/.tscn` (nuevo — confirmación en host)
- `project.godot` (autoload `RemoteControlManager` si aplica; permisos UDP/WS en export móvil)
- `addons/remote_skeleton_udp/` (reincorporar a main como base del stream UDP)

## Dependencias

- FD-263 (touch universal) para input touch coherente en móvil.
- FD-295 no bloquea; en F2 el teléfono espejará ese mismo HUD.

## Verification

1. Dos instancias en la misma LAN: CONTROL REMOTO lista la sesión viva con
   nombre y versión; sesiones muertas desaparecen tras ~6 s sin anuncio.
2. Emparejar → diálogo de confirmación en el host con PIN; rechazar o
   dejar expirar cancela; aceptar abre el canal y muestra estado conectado.
3. Host envía `ui{prompt}` y el teléfono lo muestra; un tap en el teléfono
   llega como `input{touch}` al host (log visible).
4. Accel/gyro del teléfono llegan ~30 Hz; si el stream se corta >2 s el
   host marca el dispositivo inactivo (patrón remote_skeleton_udp).
5. Corte de red a mitad de sesión: teléfono muestra "Reconectando…";
   token inválido o tercer dispositivo sin PIN → rechazado.
6. Tests gdUnit de serialize/parse del protocolo y del handshake (PIN
   incorrecto rechazado, token expira).
