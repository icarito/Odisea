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
- Captura visual: `res://core_v2/tests/test_anna_scene_visual.oys`

```bash
./runtest.sh -a ./core_v2/tests/test_anna_interface.gd
./runtest.sh --oys test_anna_scene_visual
```

Documentacion canon:

- `docs/feature_anna_agent.md`
