# FD-162: Odisea Bridge — Nodo de Telemetría y Observabilidad

## Resumen

Un peer Python que se anuncia por mDNS en la red local. Los Godots (desktop, Android, HTML5) lo descubren automáticamente y le envían su telemetría. El peer la sirve vía HTTP para agentes y la sincroniza con un nodo central que almacena el histórico. El nodo central no es público — solo accesible por agentes autorizados.

## Puerto único

| Puerto | Componente | Uso |
|--------|-----------|-----|
| 4999 | Peer Python | HTTP + WS local. mDNS se anuncia aquí. |
| 5003 | Nodo Central | HTTP + WS. No público. Solo agentes con token. |

ANNA MCP (el sistema anterior) queda deprecado. Los puertos 5000+ se reasignan: 5000 libre, 5001 reservado para WS server de ANNA V2 (mesh entre Godots, opcional), 5003 para el nodo central.

## Arquitectura

```
LAN local (descubrimiento automático por mDNS)

  Godot A (desktop)
    └── mDNS descubre peer ←── Peer Python :4999
        └── WS local envía telemetría

  Godot B (Android)
    └── mDNS descubre peer ←── Peer Python :4999
        └── WS local envía telemetría

  Godot C (HTML5 en otro cuarto)
    └── mDNS descubre peer ←── Peer Python :4999
        └── WS local envía telemetría

Peer Python :4999
  ├── mDNS: se anuncia como _odisea._tcp
  ├── HTTP: /status, /sessions, /health para agentes
  ├── WS: recibe telemetría de Godots locales
  └── WS: sincroniza con nodo central

Nodo Central :5003 (35.182.238.36)
  ├── WS: recibe telemetría de todos los peers
  ├── HTTP: /status, /sessions (requiere token, no público)
  └── Almacena ghosts como JSONL
```

## Descubrimiento (mDNS)

El peer Python se anuncia como `_odisea._tcp` en el puerto 4999.

Godot, al iniciar, busca servicios `_odisea._tcp` en la red. Cuando encuentra uno, conecta al peer por WebSocket y empieza a enviar heartbeats.

Para Godot, el descubrimiento es: buscar mDNS → conectar WS → enviar datos. Sin configuración manual.

## Heartbeat (JSON, enviado de Godot al peer, y del peer al central)

```json
{
  "schema_version": 1,
  "type": "heartbeat",
  "player_id": "uuid-persistente",
  "session_id": "uuid-por-sesion",
  "host": "hostname",
  "godot_version": "3.6.2",
  "game_version": "0.1.0",
  "platform": "desktop",
  "player": {
    "position": [12.5, 1.2, -3.8],
    "velocity": [0.1, 0.0, 0.0],
    "yaw": 1.57,
    "pitch": -0.1,
    "roll": 0.0,
    "mode": "standard",
    "scene": "Dome_Crio",
    "zone": "criogenia",
    "tick": 1423,
    "fps": 59.94,
    "memory_mb": 142.5
  },
  "timestamp": 1717800000.123
}

- **tick**: contador de frames de física determinista (Core V2).
- **fps**: frames por segundo. Para detectar regresiones de performance.
- **memory_mb**: memoria usada por el juego en MB. Para detectar memory leaks.
- **schema_version**: versión del esquema del heartbeat. Incrementar cuando se agreguen campos obligatorios.

> **Nota sobre ghosts vs replays:** Los ghosts (heartbeats a 10 Hz con posición/rotación) son una aproximación visual interpolada. NO reemplazan los replays deterministas de Core V2/OdysseyScript, que graban inputs al tick rate de física. Los ghosts sirven para observabilidad, debugging visual y detección de regresiones. Para reproducción exacta de sesiones, usar el sistema de replays de Core V2.
```

## Componentes

El FD-162 describe dos componentes que se implementan por separado, cada uno con su propio prompt y sesión de desarrollo.

### Componente A: ANNA V2 — Entry Point de Red, Plugins y Telemetría

ANNA V2 es el reemplazo de ANNA MCP. No es un plugin de Godot — es parte del runtime, un sistema que orquesta todo lo que entra y sale del juego. Es la interfaz que conecta el juego con el mundo exterior.

ANNA V2 gestiona:

| Área | Responsabilidad |
|------|----------------|
| **Plugins (.pck)** | Cargar, descargar, recargar en caliente plugins de Godot. Un plugin puede ser un nivel nuevo, un set de props, un sistema de físicas alternativo. ANNA los monta y desmonta sin reiniciar el juego. |
| **Hot-reload** | Recibir scripts GDScript nuevos (de Jules, de Codex) y recargarlos en caliente. Detectar cambios en archivos .tscn, .gd, .tres y aplicarlos al instante. |
| **Telemetría** | Loop de heartbeat cada 100ms: posición, rotación, escena, modo, FPS, memoria, tick determinista. Enviar al peer local vía WebSocket. |
| **Debugging** | API MCP extendida: inspect_node, set_property, execute_script, spawn_scene, reload_resource. Ejecutar código arbitrario en el runtime. |
| **Estado del juego** | Exponer un snapshot completo del estado actual: escena, player, modo de gravedad, cámaras activas, props cargados, FPS, memoria, número de nodos. |
| **Actualizaciones** | Recibir archivos nuevos (scripts, escenas, texturas) desde el peer y aplicarlos sin reiniciar. Sincronizar con el peer cuando hay cambios en el repo. |
| **Red** | Conectarse al peer local por WebSocket. Abrir un servidor WebSocket para recibir conexiones de otros peers o agentes. |
| **Comandos remotos** | Ejecutar acciones recibidas desde el peer: teleportear al player, spawnear un prop, cambiar la escena, ejecutar un test OYS, tomar un screenshot. |

#### ⚠️ Restricciones de implementación

**HTML5 (WebGL): no tiene mDNS.** Los navegadores bloquean UDP. Una build HTML5 no puede hacer descubrimiento mDNS. En HTML5, ANNA V2 debe:
- Intentar conectar directamente a `ws://localhost:4999/ws` por defecto.
- Aceptar un parámetro en la URL: `?bridge=192.168.1.10:4999`.
- Si no hay conexión, reintentar cada 2s sin fallar.

**Threading:** El SceneTree de Godot 3.x **no es thread-safe**. ANNA V2 NO debe ejecutar operaciones del SceneTree en su propio hilo. En lugar de eso:
- El hilo de red solo recibe datos y los mete en una cola thread-safe (un Array con mutex).
- El main thread de Godot vacía esa cola en `_process()` o `_physics_process()` usando `call_deferred()` para operaciones del SceneTree.
- Operaciones como `add_child()`, `set_property()` en nodos del árbol, o `instance()` de escenas nunca se hacen desde el hilo de red.

**mDNS en GDScript:** Godot 3.6 no tiene soporte nativo para mDNS. La implementación en GDScript debe:
- Usar `PacketPeerUDP` para unirse al grupo multicast `224.0.0.251:5353`.
- Parsear paquetes DNS para encontrar el servicio `_odisea._tcp`.
- **Apagarse inmediatamente** después del primer handshake exitoso con el peer (`set_process(false)`), liberando el socket UDP.
- Alternativa: si la implementación GDScript de mDNS es muy compleja, ANNA V2 puede escanear puertos en la red local (más lento, más simple).

**Tick determinista en heartbeat:** El campo `tick` en el heartbeat es el contador de frames de física de Core V2. Esto es necesario para que los ghosts almacenados en el central puedan reproducirse fielmente, ya que el wall-clock time varía entre máquinas.

**Arquitectura de ANNA V2 dentro de Godot:**

```
Godot Runtime
│
├── Main Thread
│   ├── Gameplay, física, render
│   └── CommandConsumer
│       └── each _process: vacía cola de comandos
│           con call_deferred()
│
├── ANNA V2 Thread (red)
│   ├── WebSocket client ←→ Peer :4999
│   ├── WebSocket server :5001 (opcional)
│   ├── mDNS Discovery (se apaga al conectar)
│   └── CommandQueue thread-safe
│       └── push comandos aquí, no ejecutar
│
└── Archivos
    ├── PluginManager
    ├── HotReloader
    └── TelemetryLoop
```

**Flag de build para control remoto:** Aunque hoy ANNA V2 es una herramienta de desarrollo, el binario que la contiene puede llegar a builds públicos. Para evitar RCE en producción, todo comando remoto que ejecute código arbitrario (execute_script, set_property, spawn_scene, reload_resource) debe estar protegido por:

```gdscript
if OS.is_debug_build() or OS.has_feature("editor"):
    ejecutar_comando()
else:
    ignorar()  # o responder "comando no disponible en release"
```

La telemetría (solo lectura) puede permanecer activa siempre, es inofensiva.

El prompt para implementar ANNA V2 está en un documento separado (referencia: FD-162-ANNA-V2).

### Componente B: Odisea Bridge Peer (Python)

Un proceso Python que corre en la máquina local. Se anuncia por mDNS y sirve como relay entre Godot, los agentes, y el nodo central.

Responsabilidades:
- **mDNS**: se anuncia como `_odisea._tcp` puerto 4999
- **WebSocket server**: recibe heartbeats de Godots locales (conectados por ANNA V2)
- **HTTP server**: `/status`, `/sessions`, `/health` para agentes
- **WebSocket client**: sincroniza con el nodo central
- **Cache local**: TTL 60s

El prompt para implementar el Bridge Peer está en un documento separado (referencia: FD-162-BRIDGE-PEER).

### Componente C: Nodo Central (Python)

Un proceso Python que corre en el servidor AWS (35.182.238.36). No tiene mDNS. No es público.

Responsabilidades:
- **WebSocket server**: recibe heartbeats de peers
- **HTTP server**: `/status`, `/sessions`, `/health` (requiere header `Authorization: Bearer <token>`)
- **Ghost storage**: opcional, escribe heartbeats a `data/ghosts/{player_id}/{session_id}.jsonl`
- **Cache**: TTL 60 segundos

## Seguridad

- **Peer local**: accesible solo en la red local (mDNS no sale al exterior). Sin autenticación.
- **Nodo central**: NO es público. Todas las rutas HTTP requieren header `Authorization: Bearer <token>`. El token se valida contra `ODISEA_BRIDGE_TOKEN`.
- La conexión WebSocket del peer al central también requiere el token en el handshake.

## Variables de entorno

| Variable | Default | Descripción |
|----------|---------|-------------|
| PEER_PORT | 4999 | Puerto del peer (HTTP + WS) |
| CENTRAL_URL | ws://35.182.238.36:5003/ws | URL del nodo central |
| CENTRAL_HTTP_PORT | 5003 | Puerto HTTP del central |
| CENTRAL_CACHE_TTL | 60 | TTL de heartbeats en central |
| CENTRAL_STORE_GHOSTS | false | Guardar ghosts como JSONL |
| ODISEA_BRIDGE_TOKEN | — | Token de autenticación (requerido en central) |
| PLAYER_ID | auto-generado | ID persistente del player |
| GODOT_VERSION | unknown | Versión del engine |
| GAME_VERSION | 0.1.0 | Versión del juego |

## Endpoints

### Peer (:4999) — red local, sin autenticación

GET /status — heartbeats de todos los Godots conectados a este peer
GET /status?player_id=xxx — heartbeat de un player específico
GET /sessions — session_ids activas
GET /health — estado del peer
WS /ws — Godots envían heartbeats aquí

### Central (:5003) — requiere token, no público

GET /status — heartbeats de todos los peers (header `Authorization: Bearer <token>`)
GET /status?player_id=xxx — heartbeat de un player (requiere token)
GET /sessions — sesiones activas (requiere token)
GET /health — estado del central
WS /ws — peers se conectan aquí

## Consultas de agente

Yo (Odiseo) consulto:

```
# Godots locales conectados a este peer (LAN, respuesta inmediata)
web_fetch("http://localhost:4999/status")

# Histórico en el central (requiere token)
web_fetch("http://35.182.238.36:5003/status",
    headers={"Authorization": "Bearer <token>"})
```

## Implementación MVP

Fase 1 — Peer Python:
- `odisea_peer.py` con mDNS + WS + HTTP :4999
- `odisea_central.py` con WS + HTTP :5003 (token requerido)
- Godot autoload que descubre peer por mDNS y envía heartbeats

Fase 2 — Agentes consultan:
- Yo consulto peer local y central
- Ghosts en central como JSONL

Fase 3 — Mesh entre peers:
- Varios peers en distintas LANs se sincronizan a través del central
- El central retransmite heartbeats entre peers (solo con autorización)
