# Feature Spec: A.N.N.A para Integracion ML/CV

## 1) Fundamentos estrategicos y arquitectura de red

A.N.N.A. (Automated Neural Network Auditor) es el puente de ejecucion entre Godot y clientes externos de IA/QA. El objetivo no es solo "leer datos", sino cerrar el loop de entrenamiento y auditoria:

- Godot simula y expone estado.
- El cliente externo decide acciones.
- Godot aplica acciones sobre `Pilot` en el siguiente tick fisico.

### Decision de arquitectura

- Transporte: TCP (integridad de paquetes y framing estable).
- Formato: JSON line-delimited (interoperable con Python y toolchains RL).
- Activacion condicional: `ANNA_ENABLED=1` en `SessionManager`.
- Puerto configurable: `ANNA_PORT` (default `5000`).

### Implementacion actual

- `core_v2/autoloads/SessionManager.gd`
  - Instancia `AnnaBridge` solo cuando `ANNA_ENABLED=1`.
- `core_v2/anna/AnnaBridge.gd`
  - Acepta clientes TCP.
  - Stream de observaciones por `_physics_process`.
  - Parsea acciones JSON por linea.
  - Cierra peers y server en `_exit_tree()`.

## 2) Contrato de observacion/accion (AnnaInterface)

`core_v2/anna/AnnaInterface.gd` concentra la capa sensorial y de actuacion.

### Observaciones emitidas

- `proximity`: interactuables dentro de 10m (`name`, `type`, `pos`, `dist`).
- `buffer`: logs recientes de consola (capado a 50 entradas).
- `metrics`: `fps`, `mem_static`, `objects`.
- `collisions`: 32 raycasts en anillo (max 20m).
- `anna`: metadata de protocolo:
  - `protocol`: `anna.v1`
  - `physics_frame`
  - `recording`
  - `heuristic_human`
  - `peer_count` (inyectado por bridge)

### Acciones consumidas

- `move: [x, y]` (clamp a `[-1, 1]`).
- `look: [x, y]` (clamp a `[-250, 250]`).
- `jump`, `interact`, `sprint`, `crouch`.
- `command` (si `allow_command_injection=true`).
- `oys` (integracion estructurada con OYS Console).
- `olcs` / `ocls` (integracion estructurada con LogicCircuitManager).

### Heuristica humana para depuracion

Si existe un controlador IA con `heuristic == "human"` (resuelto por `ai_controller_path`, nodo `AIController` o grupo `ai_controller`), la entrada manual invalida `move` remoto cuando hay input de teclado/gamepad en:

- `move_left` / `move_right`
- `move_forward` / `move_backward`

Esto permite depurar espacio de acciones antes de delegar control total al agente.

### Combinacion con OYS y OLCS/OCLS

ANNA puede coordinar tres capas en un mismo ciclo:

1. Control fisico continuo (`move`, `look`, etc.).
2. Acciones discretas de scripting (`oys.command`, `oys.run`, `oys.exec`).
3. Estimulos sobre red logica (`olcs.inject`, `olcs.set_output`, `olcs.rebuild_cables`).

Para evitar repeticion involuntaria en acciones discretas, `oys` y `olcs/ocls` soportan `once_id`.

Adicionalmente, OYS soporta una funcion `SYSTEM` para lanzar comandos externos desde `SET`:

```oys
SET $pid SYSTEM python3 core_v2/anna/client/anna_scene_visual_driver.py --frames 72
ASSERT $pid > 0 "No se pudo iniciar driver ANNA TCP"
```

Sintaxis:

```oys
SET $var SYSTEM [sync|async] <programa> [args...]
```

- `async` (default): retorna PID.
- `sync`: retorna exit code.
- error: retorna `-1`.

Para replays deterministas, los eventos `SYSTEM` se omiten en PASS 2 (replay JSON), evitando side-effects externos.

## 3) Rendimiento: estrategia GDScript vs C++ (GDExtension)

Para MVP se mantiene orquestacion en GDScript (menor costo de iteracion), bajo la regla:

- optimizar luego de perfilar.

Direccion tecnica para escalado:

- Mantener red/protocolo y glue en GDScript.
- Delegar kernels pesados (CV/sensores masivos/path logic intensivo) a GDExtension C++ cuando el profiling lo exija.
- Evitar C# como dependencia central en rutas que deban mantenerse compatibles con toolchains sin soporte .NET.

## 4) Estructuras logicas (BT/HSM) y roadmap tecnico

El bridge ANNA queda desacoplado del motor de decisiones. La capa de decision puede evolucionar en dos niveles:

- Alto nivel (Python): politica RL/QA decide el "que".
- Bajo nivel (Godot): BT/HSM ejecuta el "como" con latencia baja.

Recomendacion de integracion:

- Blackboard para intercambio de intenciones.
- LimboAI (BT en C++/GDExtension) para ejecucion local eficiente.
- Sin acoplar entrenamiento dentro del hilo principal de Godot.

## 5) Checklist MVP y estado

- [x] Activacion condicional (`ANNA_ENABLED`).
- [x] Stub cliente Python (`core_v2/anna/client/anna_client.py`).
- [x] Sensores base (`proximity`, `collisions`).
- [x] Auditoria de consola (`buffer`).
- [x] Metadata de protocolo por frame (`anna`).
- [x] Heuristica humana para invalidar movimiento IA.
- [x] Integracion estructurada con OYS (`oys` action).
- [x] Integracion estructurada con OLCS/OCLS (`olcs`/`ocls` action + snapshot).
- [x] Escena especial de validacion (`core_v2/tests/TestScene_ANNA.tscn`).
- [x] Tests GdUnit de interfaz y payload del bridge (`core_v2/tests/test_anna_interface.gd`).

## Validacion

Ejecucion selectiva:

```bash
./runtest.sh -a ./core_v2/tests/test_anna_interface.gd
```

Validacion visual de la escena especial:

```bash
./runtest.sh --oys test_anna_scene_visual
```

`test_anna_scene_visual.oys` ahora valida ANNA por TCP con `ASSERT` (sin screenshots), usando:

- `# REQUIRE_ANNA=1` para auto-enable de bridge.
- `# OYS_NODET=1` para saltar PASS 2 (replay JSON) de ese script.
- `SYSTEM` para lanzar `core_v2/anna/client/anna_scene_visual_driver.py`.

Leyenda visual de `TestScene_ANNA.tscn`:

- Verde (`InteractableBeacon`): objetivo cercano, debe aparecer en `proximity`.
- Amarillo (`FarBeacon`): objetivo lejano, debe quedar fuera de `proximity`.
- Rojo (`CollisionWall`): obstaculo para validar `collisions`.
- Cian (`ProximityRadiusMarker`): radio de proximidad (10m).

Suite completa:

```bash
./runtest.sh
```
