---
description: Observabilidad, debug y profiling en vivo (FD-162 / ANNA V2). Peer local :4999, comandos HTTP para status/posición/velocidad/escena/fps, evaluar GDScript, teleport, screenshot.
---

# /odisea-telemetry — Telemetría y debug en vivo

Fuente canonica compartida: `docs/agents/tooling.md`.

## Arranque rápido (asegurar el peer)

Todo el debug/observabilidad pasa por el **peer HTTP en :4999**. Asegurarlo es idempotente:

```bash
tools/ensure_peer.sh          # arranca el peer si /health no responde; no-op si ya corre
tools/ensure_peer.sh --status # solo reporta, no lanza
```

El **MCP `odisea-mcp`** (`core_v2/telemetry/odisea_v2_mcp_server.py`) proxya este peer. Usarlo con las tools MCP: `status`, `eval`, `inspect_node`, `set_property`, `screenshot`, `teleport_player`, etc.

### Arrancar un juego propio (autónomo)

`tools/launch_game.sh` arranca Godot, espera a que conecte al peer, y opcionalmente lleva a escena/posición:

```bash
tools/launch_game.sh --headless --scene res://core_v2/levels/interiors/Dome_Crio.tscn \
                     --pos "-6.2,-24.7,-0.4" --yaw 19.5   # autónomo
tools/launch_game.sh --scene <res://...> --pos "x,y,z"    # HEADFUL (sesión interactiva)
tools/launch_game.sh --stop                               # cerrar el juego lanzado
```

> El peer arrancado **después** del juego se detecta solo: ANNAV2 hace upgrade del central al peer local en pocos segundos.
> `set_property`/`execute_script`=`/eval`/`spawn_scene`/`teleport_player` requieren `OS.is_debug_build() or has_feature("editor")`.

## Arquitectura

```
Godot ─WS─▶ Peer :4999 (LAN, sin auth) ─WS+token─▶ Central :5003 (agrega, token Bearer)
              GET /status /eval, POST /command          GET /status (dashboard en /)
```

## Endpoints del peer (:4999)

| Ruta | Descripción |
|------|-------------|
| `GET /health` | `{ok, players_known, ...}` |
| `GET /status` | Heartbeats de todos: `{player_id: {...}}` |
| `GET /status?player_id=<id>` | Un player (404 si no está) |
| `GET /sessions` | Lista de session_ids activas |
| `GET /peers` | peer_id, hostname, ip y player_ids |
| `GET /events` | Stream SSE de heartbeats |
| `GET /eval?expr=` | Evalúa expresión GDScript en el runtime |
| `POST /command` | Ejecuta acción: `inspect_node`, `screenshot`, `teleport_player`, `set_property`, etc. |
| `POST /command/batch` | Lista ordenada de comandos en una sola llamada |

## Ejemplos

```bash
# Leer estado en vivo
curl -s http://localhost:4999/status | python3 -m json.tool

# Evaluar GDScript
curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"

# Inspeccionar árbol de escena
curl -s -XPOST localhost:4999/command -d '{"action":"inspect_node","args":{"path":"/root"}}'

# Screenshot
curl -s -XPOST localhost:4999/command -d '{"action":"screenshot"}'

# Teletransportar jugador
curl -s -XPOST localhost:4999/command -d '{"action":"teleport_player","args":{"position":[10,1,-3]}}'

# Batch (secuencia ordenada)
curl -s -XPOST localhost:4999/command/batch -d '{
  "player_id":"<id>", "stop_on_error":true,
  "commands":[
    {"action":"teleport_player","args":{"position":[10,1,-3]}},
    {"action":"screenshot"},
    {"action":"inspect_node","args":{"path":"/root/Main"}}
  ]}'
```

## Esquema del heartbeat

```json
{
  "schema_version": 1, "type": "heartbeat",
  "player_id": "uuid-persistente", "session_id": "uuid-por-sesion",
  "host": "hostname", "godot_version": "3.6.2", "game_version": "0.1.0",
  "player": {
    "position": [x,y,z], "velocity": [x,y,z], "yaw": 0.0, "pitch": 0.0,
    "mode": "standard", "scene": "Dome_Crio", "fps": 59.94, "memory_mb": 142.5
  }
}
```

## Gotchas

- **`/status` vacío (`{}`)**: no hay juego reproduciéndose. El autoload corre solo al dar play (F5).
- **Timeout en comandos modificadores**: verificar con `/eval?expr=OS.is_debug_build()`. Si es false, el build es release.
- **El peer no tiene datos pero el juego corre**: ANNAV2 descubre el peer por mDNS + UDP broadcast, reintenta cada 2-5s. Ejecutar `tools/ensure_peer.sh`.
- **Errores**: `503 no_game_connected`, `404 player_not_found`, `504 timeout` (8s), `429 rate_limited` (>10 cmd/s).
- **El `game_version` es cosmético**: NO indica si es debug o release — usar `OS.is_debug_build()`.
