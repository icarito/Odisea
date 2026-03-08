# A.N.N.A (Automated Neural Network Auditor)

Bridge TCP para integrar `core_v2` con clientes externos de ML/CV y QA automatizado.

## Objetivo

Cerrar el loop de entrenamiento/auditoria:

1. Godot envia observacion por frame fisico.
2. Cliente externo responde con accion.
3. `Pilot` ejecuta la accion dentro del loop de fisica.

## Activacion

```bash
export ANNA_ENABLED=1
export ANNA_PORT=5000 # opcional, default 5000
godot3-bin --path .
```

La integracion se activa desde `SessionManager.gd` solo cuando `ANNA_ENABLED=1`.

## Arquitectura

- `AnnaBridge.gd`
  - Server TCP + framing newline JSON.
  - Multiplex de peers.
  - Shutdown limpio en `_exit_tree`.
- `AnnaInterface.gd`
  - Recoleccion de observaciones.
  - Inyeccion de acciones sobre `Pilot`.
  - Clamping/sanitizado de acciones.

## Protocolo (line-delimited JSON)

### Observation (Godot -> Cliente)

```json
{
  "proximity": [],
  "buffer": [],
  "metrics": {
    "fps": 60.0,
    "mem_static": 0,
    "objects": 0
  },
  "collisions": [20.0],
  "anna": {
    "protocol": "anna.v1",
    "physics_frame": 123,
    "recording": false,
    "heuristic_human": false,
    "integrations": {
      "oys": true,
      "olcs": true
    },
    "peer_count": 1
  },
  "olcs": {
    "available": true,
    "manager": "LogicCircuitManager",
    "nodes": [],
    "connections": []
  } 
}
```

### Action (Cliente -> Godot)

```json
{
  "move": [0.0, -1.0],
  "look": [0.5, -0.1],
  "jump": false,
  "interact": false,
  "sprint": false,
  "crouch": false,
  "command": "echo hello"
}
```

Notas:

- `move` clamp a `[-1, 1]`.
- `look` clamp a `[-250, 250]`.
- `command` solo aplica si `allow_command_injection = true`.
- `olcs` y `ocls` se aceptan como alias para acciones del circuito.

### MCP Bridge Commands (`type: "mcp_cmd"`)

El bridge soporta comandos estilo MCP sobre el mismo socket TCP.  
Formato recomendado:

```json
{
  "type": "mcp_cmd",
  "id": "req-123",
  "payload": {
    "action": "get_tree",
    "args": {
      "max_depth": 4
    }
  }
}
```

Respuesta:

```json
{
  "type": "mcp_result",
  "id": "req-123",
  "ok": true,
  "data": {}
}
```

Recursos soportados:

- `odisea://scene/hierarchy` (`action: "get_tree"`)
- `odisea://simulation/telemetry`
- `odisea://olcs/logic-state`

Tools soportados:

- `bridge_status` (estado de conexión/proceso del puente)
- `bridge_connect` (apuntar a runtime ya levantado)
- `bridge_launch` (levantar Godot con `ANNA_ENABLED=1` y conectar)
- `bridge_reset` (reiniciar sesión Godot + reconectar)
- `bridge_stop` (detener sesión Godot lanzada por MCP)
- `inspect_node` (`action: "inspect"` o `"inspect_node"`, arg `node_path`)
- `set_property` (`action: "set_property"`, args `node_path`, `property`, `value`, opcional `strict`)
- `execute_oys` (`action: "oys_inject"` o `"execute_oys"`, arg `script_command`)
- `capture_vision` (`action: "capture_vision"`, args opcionales `label`, `include_base64`)
- `query_codex_docs` (`action: "query_codex_docs"`, args `topic`, `max_matches`)

### MCP Server para VS Code (stdio)

Script: `core_v2/anna/client/odisea_mcp_stdio_server.py`

Modos:

- **MCP stdio** (default): usado por VS Code via `.vscode/mcp.json`.
- **CLI directo** (stub):

```bash
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_status
```

```bash
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_connect \
  --args-json '{"host":"127.0.0.1","port":5000}'
```

```bash
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_launch \
  --args-json '{"project_path":".","godot_exe":"godot3-bin","port":5000}'
```

```bash
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_stop
```

También soporta recursos:

```bash
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --resource odisea://simulation/telemetry
```

### Acciones estructuradas: OYS + OLCS/OCLS

Ejecutar comandos OYS de forma controlada:

```json
{
  "oys": {
    "once_id": "boot-1",
    "command": "echo hello from anna",
    "run": "res://core_v2/tests/test_salto_vertical.oys",
    "exec": "default_env.cfg"
  }
}
```

`once_id` evita repetir acciones one-shot si el mismo payload se retransmite.

Desde OYS tambien se puede disparar clientes externos con la nueva funcion helper:

```oys
SET $pid SYSTEM python3 core_v2/anna/client/anna_scene_visual_driver.py --frames 72
ASSERT $pid > 0 "No se pudo lanzar driver TCP"
```

Sintaxis:

```oys
SET $var SYSTEM [sync|async] <programa> [args...]
```

- `async` (default): retorna PID (> 0).
- `sync`: retorna exit code del proceso.
- En error retorna `-1`.

Controlar el circuito OLCS desde ANNA:

```json
{
  "olcs": {
    "once_id": "circuit-1",
    "inject": { "target": "DoorA", "input": "LeverA", "value": true },
    "set_output": { "source": "LeverA", "value": true },
    "rebuild_cables": true
  }
}
```

Para esto `LogicCircuitManager` expone:
- `anna_get_snapshot(max_entries)`
- `anna_inject_input(target_id, input_id, value)`
- `anna_set_output(source_id, value)`
- `anna_rebuild_cables()`

## Heuristica humana

Si existe controlador IA con `heuristic == "human"`, ANNA invalida el `move` remoto cuando detecta input manual (`move_left/right/forward/backward`). Esto se usa para debugging y validacion del espacio de acciones.

Resolucion del controlador:

1. `ai_controller_path`
2. Nodo `AIController`
3. Grupo `ai_controller`

## Cliente de prueba

`core_v2/anna/client/anna_client.py` conecta, imprime resumen por frame y ejecuta random-walk.

```bash
python3 core_v2/anna/client/anna_client.py
```

## Validacion en proyecto

- Escena especial: `res://core_v2/tests/TestScene_ANNA.tscn`
- Tests: `res://core_v2/tests/test_anna_interface.gd`
- Validacion visual TCP: `res://core_v2/tests/test_anna_scene_visual.oys`
- Driver determinista: `res://core_v2/anna/client/anna_scene_visual_driver.py`

```bash
./runtest.sh -a ./core_v2/tests/test_anna_interface.gd
./runtest.sh --oys test_anna_scene_visual
```

`test_anna_scene_visual.oys` usa:

- `# REQUIRE_ANNA=1` para auto-instanciar `AnnaBridge` si falta en runtime.
- `# OYS_NODET=1` para saltar solo PASS 2 de determinismo (replay JSON) en este caso con agente externo.

El test valida movimiento real del `Pilot` via TCP con `ASSERT` (sin `SCREENSHOT`).

Documentacion canon:

- `docs/feature_anna_agent.md`
