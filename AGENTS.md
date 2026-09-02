# AGENTS.md — Guía de Desarrollo Asistido (Odisea)

Este documento define las reglas, convenciones y procesos para cualquier agente que asista en el desarrollo de *Odisea: El Arca Silenciosa* (Godot 3, GDScript 1.x).

Para navegacion entre agentes, comandos y skills, leer tambien:

- `docs/agents/README.md` — punto de entrada neutral para Codex, Claude, Gemini, Kilo y agentes genericos.
- `docs/agents/agent-map.md` — que archivo editar y que archivo solo adapta instrucciones.
- `docs/agents/tooling.md` — resumen operativo de tests, telemetria, eval headless, props y UI.
- `docs/agents/skills-index.md` — indice de workflows compartidos y adaptadores por agente.

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

**Preservar el determinismo.** El juego usa un Core determinista con replay. No introducir aleatoriedad (`randf()`, `randomize()`) en lógica de gameplay. No usar `Engine.get_frames_drawn()` ni valores no reproducibles en lógica de estado. Ver §5.3.

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

- **Godot 3.x**, GDScript 1.x. No usar `await`, `@onready`. Usar `yield()`, `connect()` con strings.
- Static typing en todo código de producción: `var x: int`, `func f(v: float) -> void:`.
- Composición sobre herencia. Señales para comunicación entre escenas. Evitar `get_parent()`.
- Cada componente < 200 líneas haciendo exactamente una cosa.
- Usar `_setting("key", default_value)` para valores configurables desde el editor.
- Ternario: `a if cond else b`. Declarar con type hints: `var x: int = 0`.
- No usar `nil` donde se esperan tipos concretos (bool, Vector2); usar valores por defecto.
- Usar `_nombre` para miembros de uso interno (no hay private/protected).

> [!IMPORTANT] BINARIO DE GODOT
> Usar siempre el alias `godot3-bin` para ejecutar Godot 3.6. El comando `godot` puede apuntar a Godot 4,
> lo que causará errores de sintaxis (`yield` vs `await`). El error `Index 1 is out of bounds (count = 1)`
> aparece *siempre* al arrancar y **no** es un problema de nuestro código.

### 2.3 Cámara y controles

- Todos los modos de juego usan el mismo `CameraRig` con su `SpringArm`. No existe un rig separado por modo.
- El zoom, el seguimiento (spring arm), y el sistema over-the-shoulder (OTS) son responsabilidad del controlador principal. Los modos especiales no deben reemplazar ni duplicar estos sistemas.
- Si un modo necesita rotación adicional (ej: roll en zero-g), se aplica como transformación adicional sobre el basis existente del `CameraRig`, sin reemplazar el rig ni el spring arm.
- La cámara nunca se debe mover ni cambiar de orientación al entrar o salir de un modo especial. El punto de vista del jugador es inviolable a través de transiciones.

### 2.4 Estructura de directorios

```
core_v2/           → Código principal (todo lo nuevo/refactorizado va acá)
core_v2/player/    → Controladores y managers
core_v2/camera/    → Rigs de cámara
core_v2/props/     → Props interactivos y decorativos
core_v2/ui/retro/  → UI OdiseaOS
core_v2/input/     → InputDataV2 y sistemas de input
core_v2/anna/      → ANNA V1 (bridge MCP) — **DEPRECATED**, reemplazado por V2
core_v2/telemetry/ → Telemetría y debugging remoto
core_v2/tests/     → Tests (GdUnit y OYS)
```

### 2.5 Normas de trabajo

- Commits pequeños y enfocados. Validar cambios en `TestScene_v2.tscn`.
- Documentar cada `export var` en el Inspector.
- Usar GdUnit3 para tests. **Todo el código nuevo o refactorizado debe ir en `core_v2`.**

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

## 5. CONTRATOS CRÍTICOS

> Estos son contratos duros del Core. Romperlos rompe física, plataformas o replays.
> **Leerlos antes de tocar gravedad, movimiento del jugador o sincronización.**

### 5.1 Gravity / WorldRotator / Plate Physics

Antes de tocar gravedad, terrazas centrífugas, `WorldRotator`, `PlateContentStream`, zero-G, scaffold infinito o `BaseTerrace`, leer:

- `docs/engineering/Gravity_Physics_Contracts.md`
- `docs/features/FD-036_gravity_manager.md`
- `docs/features/FD-039_gravity_physics_strategy.md`
- `docs/features/FD-040_plate_content_stream_stability.md`

Resumen operativo:
- `PlayerControllerV2` conserva `Vector3.UP`; no introducir `up` dinámico.
- En modo centrífugo caminable, `WorldRotator` cambia el marco visual y la cámara sigue al personaje; la física del jugador sigue siendo estándar.
- Gameplay con física debe vivir fuera de `WorldRotator` vía `PlateContentStream`, salvo escenas legacy documentadas.
- `BaseTerrace` funciona en modo centrífugo, pero sigue siendo híbrida/legacy y debe mantener `WorldRotator.centrifugal_current_plate_only_physics = false` hasta migrar su física a slots.
- `WorldRotator` es `tool`: no debe mutar transforms, seleccionar plates ni aplicar anclas en `Engine.editor_hint`.

### 5.2 PlayerController — Movimiento y Plataformas

El `PlayerControllerV2` usa **Transform-Delta Tracking** para seguir plataformas móviles (inspirado en [Terrestrial Characters](https://github.com/Trokara)):

1. **Tracking de Plataformas**: Almacena `_platform_collider` y `_platform_last_transform`. Cada frame calcula dónde *estaría* el jugador si siguiera perfectamente la plataforma:
   ```gdscript
   var old_local = platform_last_transform.affine_inverse().xform(player_pos)
   var new_global = platform.global_transform.xform(old_local)
   var delta = new_global - player_pos
   player.global_transform.origin += delta
   ```
2. **Herencia de Velocidad**: Al saltar o salir de una plataforma, hereda `_platform_velocity` para conservar momentum.
3. **Alineación a Pendientes**: `PlayerMovementV2.align_to_floor()` rota el vector de movimiento para que siga el plano del suelo, evitando drift lateral en rampas.
4. **Resistencia en Pendientes**: Ralentiza el movimiento cuesta arriba según el ángulo (configurable via `slope_resistance_factor`).
5. **Stair-Stepping**: `_try_step_up()` permite subir escalones automáticamente hasta `step_height` (default 0.4m).

**API Legacy: `set_external_velocity(v: Vector3)`** — se conserva para:
- **Conveyors**: fuerza continua sobre el jugador (necesitan `external_source_is_static = false`).
- **Efectos especiales**: knockback, viento, explosiones.
- **Objetos legacy**: compatibilidad con sistemas antiguos.

> **Nota**: Las plataformas móviles (`MovingPlatformV2`) ya NO necesitan llamar `set_external_velocity()` para el jugador — el tracking por transform lo hace automáticamente. Pero sí deben seguir llamándolo para otros cuerpos (cajas, NPCs) sin tracking propio.

- **Signals**: las señales no deben usarse para lógica que afecte el estado físico (posición, velocidad). Su uso se limita a efectos no deterministas (sonido, animaciones, UI). Ej: `PilotAnimatorV2` puede escuchar señales para disparar animaciones, pero no debe alterar el `state` del `PlayerController`.

### 5.3 Contrato de Replay Determinístico

Para garantizar replays determinísticos, todo agente sincronizado debe:

1. Pertenecer al grupo `replay_sync`.
2. Implementar `restore_snapshot(data: Dictionary)`.
3. Ejecutar toda la lógica de movimiento/simulación en `_physics_process(delta)`. **Nunca en `_process(delta)`**.
4. Consumir input a través de `InputProviderV2` (jugador) o basarse solo en estado interno (NPCs).

Verificación:
```shell
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```
Si el `drift` entre la posición final del replay y la esperada supera un umbral mínimo, el test falla, indicando ruptura del determinismo.

---

## 6. TESTS Y VALIDACIÓN

### 6.1 Antes de hacer merge

Ejecutar la suite completa para verificar que no se rompió nada:

```shell
./runtest.sh                          # recomendado (corre en paralelo)
./runtest.sh -a ./core_v2/tests//     # equivalente explícito para core_v2
```

Si algún test falla, corregirlo antes de considerar el trabajo terminado.

### 6.2 Ejecución selectiva (más rápido durante el desarrollo)

Si sabés qué test cubre tu cambio, corrélo primero:

```shell
./runtest.sh -a ./core_v2/tests/test_mi_feature.gd
```

**Solo corré TODOS los tests al final**, justo antes de mergear.

Tests principales:
- `./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd` — modos de gravedad y zero-g
- `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` — determinismo del Core

### 6.3 Leer el output de los tests

El output siempre se guarda en `./reports/gdunit_runner.log`. Si el terminal no lo muestra (común con agentes), leer el archivo:

```shell
grep -E "(PASSED|FAILED|ERROR|Total|Exit code|SCRIPT ERROR)" ./reports/gdunit_runner.log
```

### 6.4 Tests OYS

```shell
./runtest.sh --oys test_salto_vertical
```

Después de cada cambio, correr los tests relevantes al sistema modificado y verificar visualmente en el editor. Si la verificación visual revela bugs nuevos, escribir un test OYS o GdUnit que los capture antes de continuar.

### 6.5 Performance Monitoring & Stress Tests

El proyecto incluye un sistema de telemetría de performance y un harness de stress para prevenir regresiones.

- **`PerformanceMonitor` (autoload)** — `core_v2/autoloads/PerformanceMonitor.gd`. Trackea FPS, Process/Physics Time, draw calls, objects/vertices in frame, node count, y memoria. Registra métricas en `ANNAV2` (`register_telemetry_dict`) para que aparezcan en el dashboard del bridge central en tiempo real. Loguea un reporte (`user://performance_log.json`) si el FPS cae > 20 instantáneo o el CPU excede 70% del budget. Guarda snapshots manuales en `user://performance_snapshots.json` para comparación de regresión.
- **`performance_log.json`** (`user://`) — archivo que PerformanceMonitor escribe cuando detecta un lag spike. Contiene: `schema_version`, `timestamp`, `fps`, `drop`, tiempos CPU, `draw_calls`, `objects_in_frame`, `vertices_in_frame`, `node_count`, `memory_mb`, `scene` (path .tscn activa), `player_position` [x,y,z], y `heavy_nodes`. Los agentes deben consultar este archivo primero al investigar problemas de rendimiento (ver §9.2 para usarlo vía API). `scripts/analyze_ghosts.py` lo soporta como fuente alternativa cuando no hay ghosts del central.
- **Stress Test Suite** — en `core_v2/tests/stress/`. Runner `StressTestRunner.gd` (OYS Actor); `run_stress.oys` ejecuta 5 escenarios: saturación (100-1000 entidades), spawning, pathfinding, jerarquía profunda, física (RigidBody con `PushableBoxV2`).
- **Workflow de regresión** — `stress_performance.yml` corre en PRs a `main`: descarga baseline desde cache, corre `run_stress.oys` headless, compara con `scripts/check_regression.py`, y falla si FPS cae > 10% o CPU sube > 20% vs baseline.

```shell
./runtest.sh --oys stress/run_stress --show
# Resultados en ~/.local/share/godot/app_userdata/Odisea/performance_snapshots.json (Linux)
```

### 6.6 Verificación de Props

Al trabajar con Props o elementos interactuables:
1. **Ejecución**: `./test_prop.sh --target="NombreDelProp" --base64` para capturar estados visuales. Si existe `NombreDelProp.oys` junto al `.tscn` (o en `core_v2/scripts/` / `core_v2/tests/`), se ejecuta automáticamente.
2. **Reporte**: mostrar las capturas al usuario inmediatamente después de cualquier cambio en el asset.
3. **Iteración**: no considerar un asset terminado hasta que el usuario confirme que las capturas son correctas.

### 6.7 Pipeline de UI (DebugOverlay / Workbench)

Al iterar UI retro (Workbench, ventanas, terminal):

```shell
./test_ui.sh --scene=DebugOverlay --base64
./test_ui.sh --scene="res://core_v2/ui/retro/DebugOverlay.tscn"
```

- El runner usa `OYS_AUTO_RUN` sobre la escena UI objetivo. Si existe un `.oys` con el mismo basename que el `.tscn`, se usa automáticamente; si no, fallback a `core_v2/scripts/ui_validator.oys`.
- Captura al menos `*_0_boot.png`, `*_1_desktop.png`, `*_2_terminal.png`. Artefactos en `test_output/ui/`.
- Después de cambios de UI, correr `test_ui.sh` y compartir capturas antes de cerrar la iteración visual.

---

## 7. POLÍTICA DE ASSETS E IMPORTS (CI + LOCAL)

Reglas operativas:
- Los archivos trackeados dentro de `.import/` son artefactos versionados del proyecto, **no** caché descartable.
- Solo versionamos artifacts críticos de imports de escena (`.glb -> .scn/.md5`) para assets de gameplay que deban cargar en frío en CI. No versionar `.stex` masivos por defecto.
- Los pipelines normales de tests **no** deben ejecutar un clean rebuild destructivo de `.import/`. Ese camino queda reservado al workflow dedicado `Asset Integrity`.
- La lista de imports críticos vive en `ci/critical_imports.json`; la estrategia completa está en `docs/engineering/CI_Asset_Strategy.md`.
- Todo cambio que toque `assets/`, `textures/`, `models/`, `core_v2/audio/`, `core_v2/actors/`, `core_v2/components/`, `core_v2/props/`, `core_v2/levels/`, `project.godot`, `*.import` o `.import/` debe pasar validación de manifests antes de empujar.
- Si un `source_file` o `dest_files` de un `.import` trackeado no existe, es un error de integración y debe corregirse antes de CI.

```shell
python3 scripts/check_tracked_imports.py            # valida todos los manifests trackeados
python3 scripts/check_critical_import_artifacts.py  # valida imports críticos versionados
scripts/godot_import_smoke.sh --godot-bin godot3-bin --project-path . --clean-cache 0 --import-mode quick
scripts/install_git_hooks.sh                        # instala hooks repo-managed
```

- `pre-commit`: valida manifests de archivos staged + imports críticos staged.
- `pre-push`: valida todos los manifests trackeados + imports críticos, y corre smoke rápido si hay cambios de assets y existe `godot3-bin`.
- Escapes: `ODISEA_SKIP_IMPORT_HOOKS=1` (desactiva hooks), `ODISEA_SKIP_PREPUSH_SMOKE=1` (salta solo el smoke del pre-push).

---

## 8. DEVTools — DEBUGGING EN RUNTIME (sucesor de ANNA V1)

> [!WARNING] ANNA V1 DEPRECATED
> **ANNA V1** (`AnnaBridge` TCP :5000, MCP stdio) está **deprecado**. Todo el debugging remoto se hace
> vía **Telemetry** (§9): HTTP al peer `:4999` o al central `:5003`. El autoload `ANNAV2` expone comandos
> equivalentes (`inspect_node`, `screenshot`, `teleport_player`, `set_property`) a través del peer HTTP.
>
> El código legacy de ANNA V1 en `core_v2/anna/` (AnnaBridge.gd, AnnaInterface.gd, client/) se preserva
> únicamente para compatibilidad con scripts RL y OYS (`# REQUIRE_ANNA=1`). **No escribir nuevo código que
> dependa de V1.** Todo lo nuevo va a `core_v2/telemetry/`.

### Uso

```bash
# Leer estado en vivo (sin necesidad de V1)
curl -s http://localhost:4999/status | python3 -m json.tool

# Inspeccionar el árbol de escena
curl -s -XPOST localhost:4999/command -d '{"action":"inspect_node","args":{"path":"/root"}}'

# Evaluar una expresión GDScript
curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"

# Teletransportar al jugador
curl -s -XPOST localhost:4999/command -d '{"action":"teleport_player","args":{"position":[10,1,-3]}}'

# Capturar screenshot
curl -s -XPOST localhost:4999/command -d '{"action":"screenshot"}'
```

**Regla:** `GET /status` primero para ver quién está vivo; `POST /command` para actuar. Consultar §9 para la referencia completa de endpoints.

### Herencia V1 (solo para compatibilidad legacy)

El MCP stdio server (`core_v2/anna/client/odisea_mcp_stdio_server.py`) conectaba a `AnnaBridge` TCP :5000.
Permanece en el repositorio para scripts RL legacy pero **no debe usarse para nuevo código**. El equivalente
moderno es `POST /command` vía HTTP al peer :4999 (ver §9.3).

---

## 9. TELEMETRY / OBSERVABILIDAD EN VIVO (FD-162)

Cómo mirar y manejar un juego **corriendo** sin re-descubrir las herramientas cada vez.
Referencia operativa completa: skill **`odisea-telemetry`** (`/odisea-telemetry`).

### 9.0 Arquitectura

El autoload `ANNAV2` ([core_v2/telemetry/ANNAV2.gd](core_v2/telemetry/ANNAV2.gd)) emite un
**heartbeat** cada 100ms por WebSocket a un **peer** Python local, que lo sirve por HTTP y lo
reenvía a un **central** que agrega todos los peers.

```
Godot ─WS─▶ peer :4999 (LAN, sin auth) ─WS+token─▶ central :5003 (agrega, token Bearer)
              GET /status /eval, POST /command          GET /status (dashboard en /)
```

### 9.1 Asegurar el peer (idempotente)

```bash
tools/ensure_peer.sh            # arranca odisea_peer.py si /health no responde; no-op si ya corre
tools/ensure_peer.sh --status   # solo reporta
```

El **MCP `odisea-mcp`** ([core_v2/telemetry/odisea_v2_mcp_server.py](core_v2/telemetry/odisea_v2_mcp_server.py))
proxya el peer y llama a `ensure_peer.sh` solo. Configurado en `.claude/settings.json` y
`.vscode/mcp.json`. Tools: `status`, `health`, `sessions`, `peers`, `eval`, `inspect_node`,
`set_property`, `execute_script`, `screenshot`, `teleport_player`, `spawn_scene`.

> **El peer arrancado DESPUÉS del juego se detecta solo.** ANNAV2 cae al central como fallback
> si no halla peer local al boot, y luego hace *upgrade* al peer local en pocos segundos
> (`ANNAV2_Thread._maybe_upgrade_to_local_peer`, sondea `127.0.0.1:4999` cada 5s). No hace falta
> reiniciar el juego.

**Arrancar un juego propio (autónomo):** `tools/launch_game.sh [--headless] [--scene res://...]
[--pos "x,y,z"] [--yaw N] [--stop]` lanza Godot en debug (comandos habilitados), espera que
conecte al peer, y lo lleva a la escena/posición pedida (`SceneManager.goto_scene` vía `/eval`
+ `teleport_player`). Headful para revisar **con** el usuario; headless para checks autónomos
(no captura screenshots). No mata el editor abierto (`-e`).

### 9.2 Leer estado (observabilidad)

```bash
curl -s localhost:4999/status | python3 -m json.tool      # quién está vivo: scene/pos/vel/fps/mem
curl -s "localhost:4999/status?player_id=<id>"            # un player
curl -s localhost:4999/peers                              # peers y player_ids
curl -sN localhost:4999/events                            # stream SSE (en vez de polling)
# central (todos los peers, requiere token; NO imprimir el token):
curl -s -H "Authorization: Bearer $ODISEA_BRIDGE_TOKEN" https://odisea.educa.juegos/status
```

### 9.3 Manejar / debuggear el runtime (POST /command, /eval)

El peer relaya comandos al juego y devuelve la respuesta de ANNAV2 **sincrónicamente**:

```bash
curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"           # evaluar GDScript
curl -s -XPOST localhost:4999/command -d '{"action":"inspect_node","args":{"path":"/root"}}'
curl -s -XPOST localhost:4999/command -d '{"action":"screenshot"}'        # -> {"screenshot_path"}
curl -s -XPOST localhost:4999/command/batch -d '{"commands":[...]}'       # repro ordenado
```

**Gating** (`ANNAV2._can_execute_remote_command`) — dos ejes, el build y quién pregunta:

| | debug build / editor | release + peer local | release + central remoto |
|---|---|---|---|
| `inspect_node`, `screenshot` | sí | sí | **no** |
| `set_property`, `execute_script` (lo usa `/eval`), `spawn_scene`, `teleport_player`, `reload_pck`, `reload_resource` | sí | no | no |

En dev todo funciona (editor F5 y export con debug ⇒ `OS.is_debug_build()` es cierto). La
columna del medio cubre inspeccionar un export release atachándole un peer local a mano. La
tercera columna es deliberada: un build de tienda no debe ser capturable ni inspeccionable
desde el central. El origen se estampa al recibir el comando (`from_central`), no al
ejecutarlo, para que una reconexión no reclasifique lo ya encolado.

El `game_version` del heartbeat (`Constants.GAME_VERSION`, ej. `v0.3.2`) es **cosmético**, NO
indica release: no inferir el gating de ahí. Si un comando da `timeout` con el juego conectado,
verifique `/eval?expr=OS.is_debug_build()`; si ni `inspect_node` responde, el binario en
ejecución puede ser un build viejo previo al código de comandos.

**iOS no hace descubrimiento LAN.** `ANNAV2_Thread._discover_peer()` va directo al central en
iOS: sondear una IP de la LAN o bindear el UDP 5500 dispara el permiso de Red Local de iOS 14+,
que exige `NSLocalNetworkUsageDescription` — key que el preset iOS de Godot 3.6 no puede setear.
Android sí sigue descubriendo peers en la LAN (no requiere permiso).

### 9.4 Profiling / performance

- Snapshots de stress: `./runtest.sh --stress` → `~/.local/share/godot/app_userdata/Odisea/performance_snapshots.json` (ver §6.5).
- Perfilar draw calls / objetos con `VisualServer.get_render_info(...)` (Godot 3.6: usar
  `INFO_OBJECTS_IN_FRAME` + `INFO_2D_ITEMS_IN_FRAME`; `INFO_*_DRAWS_IN_FRAME` **no** existe).
- `ANNAV2.register_telemetry_point(key, value)` mezcla métricas custom en cada heartbeat.

---

## 10. ALCANCE DEL PROYECTO (ACTO I)

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

## 11. LECCIONES APRENDIDAS — 2026

### 11.1 Coordinate System (confirmado en práctica)

- **+Z = BACK**, -Z = FORWARD. Esto NO cambia.
- `camera_basis_prefix = Basis(Vector3.UP, PI)` es la rotación base del rig.
- Forward del movimiento en cualquier controlador: `-movement_basis.z`.
- Spawnear objetos frente al jugador: coordenadas Z **positivas**.
- No asumir que Godot defaults aplican — verificar con `inspect_node`.

### 11.2 CameraRig único

- Todos los modos de juego usan el mismo CameraRig con SpringArm. No existe un rig separado por modo.
- Si un modo necesita rotación adicional, se aplica como transformación sobre el basis existente, sin reemplazar el rig ni el spring arm.
- La cámara nunca se mueve ni cambia orientación al entrar/salir de un modo.

### 11.3 AirLockTransitionFX

- Usar flag `_skip_next_airlock_ready` en vez de desconectar/conectar señales para evitar race conditions.

### 11.4 Elías no es un héroe

- Elías es un oficial de mantenimiento, no un soldado ni un elegido. No tiene habilidades especiales — usa herramientas (multi-tool, Cargol).
- La tensión viene del entorno, no de combate directo. La IA Odisea es fría, dismissiva, burocrática — no abiertamente hostil.

### 11.5 Cargol como extensión, no reemplazo

- Cargol es una extensión del alcance de Elías, no un segundo personaje. No tiene HP, no es atacado directamente. Es una herramienta con limitaciones (batería, alcance).
- Su uso principal: acceder a espacios que Elías no alcanza, activar interruptores remotos.

### 11.6 Website y telemetría

- El website odisea-neon-dreams está deployado en odisea.educa.juegos/website/ (MEGA-warning de pre-pre-alfa, banner de consentimiento de telemetría, sección educativa del pipeline Godot → WebGL).
- El dashboard central (bridge FD-162) está en la raíz de odisea.educa.juegos/ con login. El peer (juego) reporta heartbeats/ghosts vía WebSocket (ver §9).

### 11.7 Export HTML5

- Firefox en Linux: "Could not create framebuffer" spamea y crashea.
- Glow desactivado para HTML5. FXAA desactivado en HTML5.
- Thread model: Single-Safe para compatibilidad sin COOP/COEP headers.
- PCK injection en HTML5: guardar en `user://` (IndexedDB), cargar con `load_resource_pack()`.

### 11.8 Anti-feature creep

- Todo lo nuevo se pregunta: ¿Está en el Acto I? ¿Es necesario para el Vertical Slice? Si no, va al backlog.
- El historial de commits muestra un patrón claro: cada vez que el MVP se acerca, aparece algo nuevo. Defender el scope con datos, no con opinión.

### 11.9 Renderer GLES3 en iOS (confirmado en device)

- El proyecto corre **GLES3 en todas las plataformas** (GLES2 solo como `fallback_to_gles2`). La pila de workarounds GLES2-iOS quedó obsoleta: `IOSLightmapFallback.gd` es opt-in (`ODISEA_MANUAL_LIGHTMAP=1`).
- **`shader_compilation_mode.iOS=0` es un contrato**: async+ubershader (modo ≥1) en GLES3 escondía meshes sin loguear NADA en device (Pilot_V2 y los `.glb` invisibles, log limpio). No subirlo a async en iOS sin warmup de shaders por escena. Causa raíz, evidencia y checklist: `docs/engineering/Renderer_GLES3_iOS.md`.
- Diagnóstico rápido en device: Opciones → Overlay de log (lee `user://logs/godot.log`). El boot siempre imprime `Async. shader compilation: ...` y `Shader cache: ...` — esa línea dice qué camino tomó el driver. iOS exporta siempre en release (comandos remotos ANNAV2 bloqueados): el diagnóstico es el overlay, no telemetría.
- En `project.godot` gana la **última** línea de override cuyo feature tag matchea (se procesa en orden de archivo). `.iOS` debe quedar después de `.mobile`/`.web` — no reordenar.
- Bug de clases "silencioso": log limpio + mesh invisible = fallo del camino de fallback del motor (ubershader), no shader roto. Antes de culpar al material, verificar el renderer y el modo de compilación.
