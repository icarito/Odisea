# AGENTS.md — Guía de Desarrollo Asistido (Odisea)

Este documento define las reglas, convenciones y procesos para cualquier agente que asista en el desarrollo de *Odisea: El Arca Silenciosa* (Godot 3, GDScript 1.x).

---

## 1. REGLAS FUNDAMENTALES

### 1.1 Inmersión ante todo

Al desarrollador le obsesiona la inmersión. Esto significa:

- **No hay transiciones bruscas.** La cámara nunca debe saltar, rotar 180°, ni teletransportarse. El punto de vista del jugador permanece constante al cambiar de modo o escena.
- **No hay glitches visuales.** Si algo parpadea, se ve fuera de lugar, o rompe la ilusión, debe corregirse antes de seguir.
- **El movimiento del jugador nunca se interrumpe.** Velocidad, momentum y dirección se preservan a través de transiciones. No hay reseteo de velocidad ni zeroing.
- **Consistencia sensorial.** Si en modo normal la cámara está detrás del personaje, en cualquier otro modo debe verse igual. No cambia la relación cámara-personaje, solo cambia el esquema de controles.

### 1.2 Principios de implementación

**Un archivo a la vez.** Resolvé bugs cambiando un solo archivo a menos que sea explícitamente necesario tocar más de uno. Si el síntoma está en un controlador, no modifiques escenas, otros controladores, o sistemas no relacionados.

**Cambios pequeños, no reescrituras.** No reescribas archivos completos. Cambios de 5-10 líneas por bug. Cada cambio debe tener una hipótesis clara antes de implementarse.

**Después de cada cambio:** corré los tests. El proyecto tiene una suite de tests que debe pasar antes de considerar un cambio completo.

**No duplicar sistemas existentes.** Si el juego ya tiene un sistema de cámara, zoom, spring arm o input, úsalo en lugar de crear uno nuevo. Extendelo antes de reemplazarlo.

**Preservar el determinismo.** El juego usa un Core determinista con replay. No introducir aleatoriedad (`randf()`, `randomize()`) en lógica de gameplay. No usar `Engine.get_frames_drawn()` ni valores no reproducibles en lógica de estado.

### 1.3 Proceso de debugging

1. **Observá** — describí el comportamiento actual sin inferir causas
2. **Referencia** — describí el comportamiento deseado (basado en cómo funciona otro modo o estado correcto conocido)
3. **Hipótesis** — una causa posible, basada en leer el código
4. **Cambio mínimo** — modificá solo lo necesario para probar la hipótesis
5. **Test** — corré la suite de tests + verificación visual
6. **Reportá** — qué cambió, qué mejoró, qué sigue roto
7. **Repetí** — volvé al paso 3

No intentes resolver todos los síntomas a la vez. Uno por uno.

---

## 2. CONVENCIONES DEL PROYECTO

### 2.1 Sistema de coordenadas

> [!WARNING] SISTEMA DE COORDENADAS NO ESTÁNDAR
> Este proyecto usa **+Z como BACK** (dirección de la cámara) y **-Z como FORWARD**.
> Esto es contrario a lo que Godot asume por defecto. El rig de cámara tiene una rotación base de 180° en Y.
> **Siempre verificar direcciones visualmente o con `inspect_node`.** No asumir que las convenciones estándar aplican.

Consecuencias prácticas:
- El forward del movimiento en cualquier controlador es `-movement_basis.z`, no `movement_basis.z`.
- La yaw almacenada en `body.yaw` es la fuente de verdad para la orientación horizontal. No recalcularla desde la basis del rig.
- Spawnear objetos frente al jugador usa coordenadas Z positivas.

### 2.2 Código (GDScript 1.x)

- **Godot 3.x**, GDScript 1.x. No usar `await`, `@onready`, `is`, `match`. Usar `yield()`, `connect()` con strings.
- Static typing en todo código de producción: `var x: int`, `func f(v: float) -> void:`.
- Composición sobre herencia. Señales para comunicación entre escenas. Evitar `get_parent()`.
- Cada componente < 200 líneas haciendo exactamente una cosa.
- Usar `_setting("key", default_value)` para valores configurables desde el editor.

### 2.3 Cámara y controles

- Todos los modos de juego usan el mismo `CameraRig` con su `SpringArm`. No existe un rig separado por modo.
- El zoom, el seguimiento (spring arm), y el sistema over-the-shoulder (OTS) son responsabilidad del controlador principal. Los modos especiales no deben reemplazar ni duplicar estos sistemas.
- Si un modo necesita rotación adicional (ej: roll en zero-g), se aplica como transformación adicional sobre el basis existente del `CameraRig`, sin reemplazar el rig ni el spring arm.
- La cámara nunca se debe mover ni cambiar de orientación al entrar o salir de un modo especial. El punto de vista del jugador es inviolable a través de transiciones.

### 2.4 Estructura de directorios

```
core_v2/           → Código principal
core_v2/player/    → Controladores y managers
core_v2/camera/    → Rigs de cámara
core_v2/props/     → Props interactivos y decorativos
core_v2/ui/retro/  → UI OdiseaOS
core_v2/input/     → InputDataV2 y sistemas de input
core_v2/tests/     → Tests (GdUnit y OYS)
```

---

## 3. CÓMO DAR INSTRUCCIONES EFECTIVAS

Un buen prompt tiene esta estructura:

```
SÍNTOMA: [qué pasa exactamente]
REFERENCIA: [cómo se ve cuando funciona bien; ej: "en modo normal la cámara está detrás del personaje"]
ARCHIVOS PERMITIDOS: [lista de archivos que puede modificar]
ARCHIVOS PROHIBIDOS: [lista de archivos que no debe tocar bajo ningún concepto]
REGLAS: [2-3 reglas clave, ej: "la cámara no debe moverse al entrar/salir"]
PROCEDIMIENTO:
1. Leer los archivos relevantes
2. Formar hipótesis de una posible causa
3. Hacer UN cambio pequeño
4. Correr tests
5. Reportar resultado
```

**Lo que NO funciona:**
- Describir bugs en excesivo detalle técnico asumiendo la solución — el agente se confía, implementa mal, y hay que rehacerlo.
- Pedir cambios arquitectónicos grandes ("reescribí este controlador", "creá un nuevo sistema de cámara") — introduce bugs nuevos y pierde fixes anteriores.
- No especificar archivos prohibidos — el agente modifica archivos no relacionados y rompe sistemas que funcionaban.

---

## 4. ARCHIVOS DE ESPECIFICACIONES (PARA GENERACIÓN AUTOMÁTICA)

El proyecto recibe código generado automáticamente a partir de specs. Las specs deben ser explícitas sobre:

- Clase base de la que hereda (ej: `PropBaseV2`)
- Nombres esperados de nodos hijos (ej: `Head`, `Bulb`, `SpotLight`)
- API exacta de métodos públicos que debe implementar
- Paths de recursos existentes que debe reusar
- Variables exportadas con tipos y rangos (Godot 3 exports)
- Escena de test mínima para verificar el comportamiento

---

## 5. ANNA / MCP — DEBUGGING EN RUNTIME

El proyecto usa un bridge MCP para inspeccionar y modificar el runtime de Godot.

### Herramientas disponibles

| Herramienta | Uso |
|-------------|-----|
| `inspect_node` | Ubicar nodos, medir posiciones/distancias, leer propiedades, contar hijos |
| `capture_vision` | Capturar imagen del viewport (solo con autorización) |
| `set_property` | Mover objetos, cambiar valores en runtime para debugging |

### Verificar conexión

```shell
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_connect \
  --args-json '{"host":"127.0.0.1","port":5000,"timeout_s":3.0}'
```

### Ejemplos de debugging

```shell
# Inspeccionar un nodo
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool inspect_node \
  --args-json '{"node_path":"/root/Pilot"}'

# Mover un objeto en runtime
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool set_property \
  --args-json '{"node_path":"/root/ZeroGravityZone","property":"global_transform","value":"Transform(1,0,0,0,1,0,0,0,1,0,1,0)"}'
```

---

## 6. TESTS

- Los tests se corren con `./runtest.sh -a <ruta_al_test>`.
- Después de cada cambio, correr los tests relevantes al sistema modificado.
- Siempre verificar visualmente en el editor después de que los tests pasen.
- Si la verificación visual revela bugs nuevos, escribir un test OYS o GdUnit que los capture antes de continuar.
- Tests principales:
  - `./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd` — modos de gravedad y zero-g
  - `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` — determinismo del Core

---

## 7. ALCANCE DEL MVP

**Dentro del alcance (Acto I):**
- Módulo Criogenia (entorno y narrativa)
- Elías (personaje jugable)
- Cargol (drón compañero)
- DDC (drone enemigo, sigilo)
- IA Odisea (diálogos, manipulación)
- Multi-tool (herramienta de mantenimiento)
- Mecánicas: movimiento, interacción, puzzle reparación, sigilo

**Fuera del alcance (backlog):**
- Todo lo que no esté listado arriba. Si un agente propone algo nuevo, debe preguntar antes de implementar. Las ideas creativas son válidas pero van al backlog.

---

## 8. LECCIONES APRENDIDAS — 2026

### 8.1 Coordinate System (confirmado en práctica)

- **+Z = BACK**, -Z = FORWARD. Esto NO cambia.
- `camera_basis_prefix = Basis(Vector3.UP, PI)` es la rotación base del rig.
- Forward del movimiento en cualquier controlador: `-movement_basis.z`.
- Spawnear objetos frente al jugador: coordenadas Z **positivas**.
- No asumir que Godot defaults aplican — verificar con `inspect_node`.

### 8.2 CameraRig único

- Todos los modos de juego usan el mismo CameraRig con SpringArm.
- No existe un rig de cámara separado por modo.
- Si un modo necesita rotación adicional, se aplica como transformación sobre el basis existente, sin reemplazar el rig ni el spring arm.
- La cámara nunca se mueve ni cambia orientación al entrar/salir de un modo.

### 8.3 AirLockTransitionFX

- Usar flag `_skip_next_airlock_ready` en vez de desconectar/conectar señales para evitar race conditions.

### 8.4 Elías no es un héroe

- Elías es un oficial de mantenimiento, no un soldado ni un elegido.
- No tiene habilidades especiales — usa herramientas (multi-tool, Cargol).
- La tensión viene del entorno, no de combate directo.
- La IA Odisea es fría, dismissiva, burocrática — no abiertamente hostil.

### 8.5 Cargol como extensión, no reemplazo

- Cargol es una extensión del alcance de Elías, no un segundo personaje.
- No tiene HP, no es atacado directamente. Es una herramienta con limitaciones (batería, alcance).
- Su uso principal: acceder a espacios que Elías no alcanza, activar interruptores remotos.

### 8.6 Website y telemetría

- El website odisea-neon-dreams está deployado en odisea.educa.juegos/website/
- Incluye: MEGA-warning de pre-pre-alfa, banner consentimiento telemetría, sección educativa pipeline Godot → WebGL
- El dashboard central (bridge) está en la raíz de odisea.educa.juegos/ con login incluido
- El peer (juego) reporta heartbeats/ghosts vía WebSocket al central

### 8.7 Export HTML5

- Firefox en Linux: "Could not create framebuffer" spamea y crashea
- Glow desactivado para HTML5
- Thread model: Single-Safe para compatibilidad sin COOP/COEP headers
- FXAA: desactivar en HTML5
- PCK injection en HTML5: guardar en user:// (IndexedDB), cargar con load_resource_pack()

### 8.8 Anti-feature creep

- Todo lo nuevo se pregunta: ¿Está en el Acto I? ¿Es necesario para el Vertical Slice? Si no, va al backlog.
- El historial de commits muestra un patrón claro: cada vez que el MVP se acerca, aparece algo nuevo.
- Defender el scope con datos, no con opinión.

---

## 9. ANNA V2 — SISTEMA DE TELEMETRÍA Y CONTROL REMOTO

### 9.1 Arquitectura General

```
┌─────────────┐     WebSocket      ┌──────────────┐
│   Peer      │ ◄──────────────►   │   Central    │
│  (Godot 3)  │     wss://.../ws   │  (Python)    │
│             │                    │  :5003       │
│ ANNAV2_Thread│                    │ Dashboard    │
│ ANNAV2_Thread_Web│                │ React SPA   │
└─────────────┘                    └──────────────┘
```

- **Peer**: El juego Godot ejecutándose. Corre ANNAV2 en un thread separado (o variante Web en HTML5).
- **Central** (`odisea_central.py`): Servidor Python aiohttp que recibe heartbeats, ghosts, y retransmite comandos.
- **Dashboard**: Frontend React que consume la API REST del Central y muestra peers conectados.

### 9.2 Peer — ANNAV2 (Godot 3, GDScript 1.x)

#### Archivos clave
| Archivo | Función |
|---------|---------|
| `core_v2/anna/v2/ANNAV2.gd` | Punto de entrada. Crea el thread y maneja conexión. |
| `core_v2/anna/v2/ANNAV2_Thread.gd` | Lógica de conexión para desktop (thread nativo). |
| `core_v2/anna/v2/ANNAV2_Thread_Web.gd` | Lógica de conexión para HTML5 (sin thread real, WebSocket nativo del browser). |
| `core_v2/autoloads/PerformanceMonitor.gd` | Recolecta FPS, CPU, draw calls para enviar como telemetría. |
| `core_v2/autoloads/SessionManager.gd` | Gestiona sesiones de juego y activa/desactiva ANNA. |

#### Flujo de conexión
1. `SessionManager` arranca y decide si habilita ANNA (por env var `ANNA_ENABLED=1` o config de Switch).
2. `ANNAV2` crea su thread con `_central_url = "wss://odisea.educa.juegos/ws"`.
3. El thread conecta al Central vía WebSocket.
4. Handshake: envía `{action: "auth", token: "..."}`.
5. Si auth ok, el peer comienza a enviar heartbeats periódicos y ghosts de sesión.
6. El Central puede enviar comandos de vuelta (reload_pck, commands).

#### Variables de entorno
| Variable | Default | Descripción |
|----------|---------|-------------|
| `ANNA_ENABLED` | (vacio) | `1` para habilitar ANNA |
| `ANNA_PORT` | `5000` | Puerto del bridge local |
| `ODISEA_ALLOW_ANNA_REMOTE_DEBUG` | (vacio) | `1` para forzar ANNA en remote debug |
| `CENTRAL_WS_URL` | `wss://odisea.educa.juegos/ws` | URL del central |

#### Heartbeats
El peer envía periódicamente:
```json
{
  "type": "heartbeat",
  "peer_id": "uuid",
  "session_id": "uuid",
  "timestamp": 1234567890.123,
  "metrics": {
    "fps": 60,
    "cpu_budget_ms": 14.2,
    "draw_calls": 150,
    "nodes": 420
  }
}
```

#### Ghosts (grabación de sesión)
El peer graba inputs y estados como "ghosts" para reproducción:
```json
{
  "type": "command_response",
  "action": "ghost_upload",
  "peer_id": "uuid",
  "session_id": "uuid",
  "data": { "frames": [...] }
}
```

### 9.3 Central — odisea_central.py

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/` | GET | Sirve el dashboard SPA |
| `/health` | GET | Health check + métricas |
| `/status` | GET | Estado de peers conectados |
| `/sessions` | GET | Lista de sesiones históricas |
| `/sessions/<player>/<session>` | GET | Descarga de sesión específica |
| `/ws` | WS | WebSocket para peers |
| `/events` | WS | WebSocket para dashboard (eventos en vivo) |
| `/command` | POST | Enviar comando a un peer |
| `/ghosts` | GET | Lista de ghosts disponibles |

#### Payload de comandos
```json
{
  "action": "reload_pck",
  "target": "peer_uuid",       // peer específico o "broadcast"
  "args": {
    "pck_url": "https://...",
    "scene": "res://scenes/Main.tscn"
  }
}
```

### 9.4 MCP — Debugging en Runtime

El proyecto incluye un bridge MCP para inspeccionar el runtime desde VS Code:

```shell
python3 core_v2/anna/client/odisea_mcp_stdio_server.py \
  --tool bridge_connect \
  --args-json '{"host":"127.0.0.1","port":5000,"timeout_s":3.0}'
```

Herramientas: `inspect_node`, `capture_vision`, `set_property`, `bridge_connect`.

### 9.5 Dashboard React (odisea.educa.juegos)

- **URL**: `odisea.educa.juegos/dashboard` o `odisea.educa.juegos/` (según deploy)
- **Autenticación**: Login con token (bearer token en sessionStorage)
- **Vistas**: PlayerCard por peer, timeline de sesiones, health metrics, ghost viewer 3D
- **Variables de entorno del build**: `VITE_API_URL` (base path para llamadas API)

