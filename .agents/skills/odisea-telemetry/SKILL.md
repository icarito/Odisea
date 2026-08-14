---
name: odisea-telemetry
description: Observabilidad, debug y profiling en vivo de los juegos Odisea (ANNA V2 / bridge FD-162). Peer local :4999 (sin auth) y central :5003 (token Bearer). Usar para status/posición/velocidad/escena/fps, sesiones activas, observar varios Godots, inspeccionar el árbol vivo, evaluar GDScript en el runtime, set_property/teleport/screenshot, o debuggear por qué el juego no aparece en la telemetría. Cubre cómo asegurar el peer y el MCP `odisea-mcp`.
---

# Odisea — Observabilidad, debug y profiling en vivo (FD-162 / ANNA V2)

Fuente canonica compartida para agentes: `docs/agents/tooling.md`. Esta skill conserva
detalles especificos para Codex y referencias historicas.

## Arranque rápido (asegurar el peer)

Todo el debug/observabilidad pasa por el **peer HTTP en :4999**. Asegurarlo es idempotente:

```bash
tools/ensure_peer.sh          # arranca el peer si /health no responde; no-op si ya corre
tools/ensure_peer.sh --status # solo reporta, no lanza
```

El **MCP `odisea-mcp`** ([core_v2/telemetry/odisea_v2_mcp_server.py](../../../core_v2/telemetry/odisea_v2_mcp_server.py))
proxya este peer y **llama a `ensure_peer.sh` solo**, así que las tools MCP (`status`, `eval`,
`inspect_node`, `set_property`, `screenshot`, `teleport_player`, …) funcionan sin pasos previos.
También sirve como CLI: `python3 core_v2/telemetry/odisea_v2_mcp_server.py --tool eval --args-json '{"expr":"..."}'`.

### Arrancar un juego propio y colocarlo en escena/estado (autónomo)

Para no depender de que un humano mantenga el juego abierto, `tools/launch_game.sh` arranca
Godot (debug build → comandos habilitados), espera a que conecte al peer, y opcionalmente lo
lleva a una escena y posiciona al jugador — todo por el mismo path de comandos del peer:

```bash
tools/launch_game.sh --headless --scene res://core_v2/levels/interiors/Dome_Crio.tscn \
                     --pos "-6.2,-24.7,-0.4" --yaw 19.5   # autónomo, sin ventana
tools/launch_game.sh --scene <res://...> --pos "x,y,z"    # HEADFUL (sesión interactiva: ver juntos)
tools/launch_game.sh --stop                               # cerrar el juego que lancé
```

El juego queda corriendo detached; seguí con `curl`/MCP. **Headless no captura screenshots**
(no hay viewport): para validar visualmente lanzá headful. No mata el editor de Godot abierto
(`-e`), solo el binario de juego que lanzó. La escena se cambia con
`get_node('/root/SceneManager').goto_scene('res://...')` vía `/eval`; el script espera a que la
escena esté viva antes de teleportar.

> El peer arrancado **después** del juego ahora se detecta solo: ANNAV2 redescubre y hace
> *upgrade* del central al peer local en pocos segundos (fix en `ANNAV2_Thread._maybe_upgrade_to_local_peer`).
> Control activo (`set_property`/`execute_script`=`/eval`/`spawn_scene`/`teleport_player`) requiere
> `OS.is_debug_build() or has_feature("editor")` — **cierto en dev (editor F5 y export con debug)**.
> `inspect_node`/`screenshot`/`reload_pck` van siempre. **Ojo:** el `game_version` del heartbeat
> (ej. `v0.3.2`, de `Constants.GAME_VERSION`) es cosmético y **NO** indica si es release — no inferir
> el gating de ahí. Si un comando da `timeout` con el juego conectado, confirmá con
> `/eval?expr=OS.is_debug_build()`; si el juego ni responde a `inspect_node`, el binario puede ser
> un build viejo sin el código de comandos.

# Odisea — Telemetría en vivo (FD-162)

Los juegos Odisea (Godot 3.6, autoload `ANNAV2`) transmiten un **heartbeat** cada 100ms
por WebSocket a un **peer** Python local. El peer lo sirve por HTTP y lo reenvía a un
**nodo central** que agrega todos los peers. Para leer el estado **se consulta por HTTP**
— ANNA MCP (puerto 5000, V1) está deprecado para telemetría.

```
Godot A ─┐
Godot B ─┼─WS─▶ Peer :4999 (LAN, sin auth) ─WS+token─▶ Central :5003 (agrega todo, token)
Godot C ─┘         GET /status, /sessions, /peers          GET /status, /sessions
```

Archivos: [odisea_peer.py](../../../odisea_peer.py), [odisea_central.py](../../../odisea_central.py),
diseño en [docs/features/FD-162-odisea-bridge.md](../../../docs/features/FD-162-odisea-bridge.md).

## Cuál usar

- **Peer (`http://localhost:4999`)** — juegos en la **misma LAN**, respuesta inmediata, **sin
  auth**. Para debugging local rápido. Lo levanta el dev con la task de VS Code
  "Run Odisea Bridge Peer" (o `python3 odisea_peer.py`).
- **Central (`:5003`)** — **todos** los peers agregados (histórico, multi-LAN). **Requiere
  token**. Default AWS: `http://35.182.238.36:5003`. Tiene además un dashboard web en `/`.

## Endpoints

| Ruta | Peer | Central | Devuelve |
|------|:----:|:-------:|----------|
| `GET /health` | ✅ pública | ✅ pública | `{ok, players_known/peers_connected, ...}` |
| `GET /status` | ✅ | 🔑 token | heartbeats de todos: `{player_id: {...}}` |
| `GET /status?player_id=<id>` | ✅ | 🔑 token | un player (404 si no está) |
| `GET /sessions` | ✅ | 🔑 token | lista de session_ids activas |
| `GET /peers` | ✅ | — | peer_id, hostname, ip y player_ids conectados |
| `GET /events` | ✅ sin auth | 🔑 token | stream SSE de heartbeats (en vez de hacer polling) |
| `GET /eval?expr=` | ✅ sin auth | — | atajo: evalúa una expresión GDScript en el runtime |
| `POST /command` | ✅ sin auth | 🔑 token | ejecuta una acción en el runtime y devuelve la respuesta |
| `POST /command/batch` | ✅ sin auth | — | ejecuta una lista ordenada de comandos en una sola llamada |
| `GET /` | — | ✅ | dashboard de observabilidad en vivo |

## Manejar el runtime (POST /command)

El peer no es solo lectura: relaya comandos al juego vivo por WebSocket y devuelve la
respuesta de ANNAV2 **sincrónicamente** (un solo `curl`). Es el loop natural de debug:
`GET /status` para ver quién está vivo → `POST /command` para inspeccionar/actuar.

### Seguridad: Console primero

Después de cada comando de inspección o mutación, revisar la **Debug Console de
VSCode**. El HTTP del peer puede resumir o perder un `Node not found` / `SCRIPT ERROR`
que sí aparece en el motor. No probar paths con `get_node()` a ciegas: usar
`inspect_node`, `get_node_or_null()` o hijos por índice. Si ANNA devuelve timeout o
genera errores de consola, detener la ráfaga de comandos; el bridge debe fallar de
forma controlada y nunca bloquear ni crashear Godot.

Acciones soportadas por ANNAV2 ([core_v2/telemetry/ANNAV2.gd](../../../core_v2/telemetry/ANNAV2.gd)):
`inspect_node`, `screenshot`, `reload_pck` (siempre disponibles), y `set_property`,
`execute_script`, `spawn_scene`, `reload_resource`, `teleport_player` (solo en debug/editor build —
en un export release dan `timeout`).

```bash
# inspeccionar un nodo del árbol vivo
curl -s -XPOST localhost:4999/command \
  -d '{"action":"inspect_node","args":{"path":"/root"}}'

# si hay varios juegos conectados, apuntá a uno con player_id (de /status)
curl -s -XPOST localhost:4999/command \
  -d '{"action":"inspect_node","player_id":"<id>","args":{"path":"/root/Main"}}'

# screenshot: el peer decodifica el PNG a disco y devuelve {"screenshot_path": "..."}
curl -s -XPOST localhost:4999/command -d '{"action":"screenshot"}'
# -> abrir/Read el screenshot_path devuelto (default /tmp/odisea_peer/shot-*.png)
```

Errores: `503 no_game_connected` (ningún Godot conectado al peer), `404 player_not_found`
(player_id no existe), `504 timeout` (el juego no respondió en PEER_COMMAND_TIMEOUT, def 8s),
`429 rate_limited` (>10 cmd/s). En el central el mismo POST requiere `player_id` y token.

### Atajos del loop de debug (solo peer)

```bash
# /eval — una expresión GDScript sin escapar un bloque. Envuelve como `return <expr>`.
curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"
curl -s "localhost:4999/eval?expr=SessionManager.player.global_transform.origin"

# /events — stream SSE de heartbeats (mirar en vez de hacer polling). Filtrable por player.
curl -sN localhost:4999/events
curl -sN "localhost:4999/events?player_id=<id>"

# /command/batch — secuencia ordenada en una llamada (ideal para capturar un repro).
curl -s -XPOST localhost:4999/command/batch -d '{
  "player_id":"<id>", "stop_on_error":true,
  "commands":[
    {"action":"teleport_player","args":{"position":[10,1,-3]}},
    {"action":"screenshot"},
    {"action":"inspect_node","args":{"path":"/root/Main"}}
  ]}'
# -> {"results":[{action,ok,status,response}, ...]}; con stop_on_error corta al primer ok:false.
```

## Autenticación del central

El central pide header **`Authorization: Bearer <token>`** (NO un query param). El token es
el env var **`ODISEA_BRIDGE_TOKEN`** con el que se arrancó el central. `/health` es pública.

- **Nunca** hardcodees ni imprimas el token en logs/transcripts. Tomalo de
  `$ODISEA_BRIDGE_TOKEN` o pedíselo al usuario en el momento.

## Ejemplos

Peer local (sin auth):
```bash
curl -s http://localhost:4999/status | python3 -m json.tool
curl -s "http://localhost:4999/status?player_id=<id>"
curl -s http://localhost:4999/peers
```

Central (con token desde el env):
```bash
curl -s -H "Authorization: Bearer $ODISEA_BRIDGE_TOKEN" http://35.182.238.36:5003/status | python3 -m json.tool
curl -s -H "Authorization: Bearer $ODISEA_BRIDGE_TOKEN" "http://35.182.238.36:5003/status?player_id=<id>"
curl -s -H "Authorization: Bearer $ODISEA_BRIDGE_TOKEN" http://35.182.238.36:5003/sessions
curl -s http://35.182.238.36:5003/health   # pública
```

Con la herramienta **WebFetch** (preferida para lecturas simples): pedí
`http://localhost:4999/status`. Para el central, WebFetch no manda headers de auth — usá
`curl` con el Bearer, o consultá el dashboard.

Dashboard web del central: abrir `http://<central>:5003/` e ingresar el token como contraseña;
muestra todos los players en vivo (refresco 1s).

## Esquema del heartbeat

```json
{
  "schema_version": 1, "type": "heartbeat",
  "player_id": "uuid-persistente", "session_id": "uuid-por-sesion",
  "host": "hostname", "godot_version": "3.6.2", "game_version": "0.1.0", "platform": "desktop",
  "peer_id": "<inyectado por el peer>", "timestamp": 1717800000.123,
  "player": {
    "position": [x,y,z], "velocity": [x,y,z], "yaw": 0.0, "pitch": 0.0, "roll": 0.0,
    "mode": "standard", "scene": "Dome_Crio", "zone": "criogenia",
    "tick": 1423, "fps": 59.94, "memory_mb": 142.5
  }
}
```
`player.{...}` puede incluir data points custom registrados por controllers vía
`ANNAV2.register_telemetry_point(key, value)` (ver skill `run-odisea`).

## Gotchas

- **`/status` vacío (`{}`)**: no hay juego *reproduciéndose*. El autoload ANNAV2 corre solo al
  dar play (F5), no con el editor abierto. Confirmá que el juego está corriendo.
- **El peer no tiene datos** pero el juego corre: ANNA V2 descubre el peer por mDNS
  (`_odisea._tcp`) + UDP broadcast y reintenta cada 2-5s; corré `tools/ensure_peer.sh`. Si el
  juego arrancó **antes** que el peer y se conectó al central como fallback, hace *upgrade*
  al peer local en pocos segundos (sondea `127.0.0.1:4999` cada 5s mientras está en central).
- **El central no tiene datos** pero el peer sí: el peer debe sincronizar con *ese* central.
  Apuntalo con `CENTRAL_WS_URL=ws://<central>:5003/ws` y el **mismo** `ODISEA_BRIDGE_TOKEN`
  (si no coincide, el central responde `invalid_token` en el handshake).
- **401 en el central**: token ausente o incorrecto en el header `Authorization: Bearer`.
- **429 en el central**: demasiados tokens inválidos desde tu IP — el central bloquea por
  fuerza bruta (`CENTRAL_AUTH_MAX_FAILS`, default 8, en `CENTRAL_AUTH_FAIL_WINDOW` 60s →
  lockout `CENTRAL_AUTH_LOCKOUT` 300s). Respetá el header `Retry-After`. Un token válido
  limpia el contador; durante el lockout hasta el token correcto recibe 429 (bloqueo por IP).
- **Edad del heartbeat**: el central expira entradas tras `CENTRAL_CACHE_TTL` (60s). Un
  `timestamp` viejo = player desconectado hace rato.
