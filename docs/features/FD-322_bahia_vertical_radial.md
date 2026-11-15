# FD-322: Bahía de máquinas vertical radial (pozo de 3 niveles)

**Status:** Implemented (greybox)
**Priority:** P1
**Effort:** Large
**Created:** 2026-11-14
**Rama:** `ao/redise-o-de/root/bahia-vertical-radial`
**Contratos:** `.operator-shared/specs/machine-launch.md`, `.operator-shared/specs/machine-layout.md`, AGENTS.md §5 (determinismo), §2.1 (sistema de coordenadas: +Z = back)
**Relacionados:** FD-320 (bahía actual), FD-050/.1/.2 (scaffold WFC), FD-314 (streaming ringhub), FD-037 (campo infinito), FD-052/v2 (MST polar duct maze), FD-053 (airlock), FD-035 (conveyor/carrousel), FD-045 (gas), FD-051 (fuego), FD-244 (multitool láser/gloo), FD-298 (linterna)

---

## 1. Visión

Rediseño de la Bahía de máquinas a un **pozo radial vertical de 3 niveles** (planta,
entrepiso, cima), armado con chunks compatibles con Wave Function Collapse en anillo
(reusando `ScaffoldOrbit` como patrón de proyección y `ScaffoldWFCGenerator` /
`ScaffoldMSTGenerator` + módulos de `core_v2/props/scaffold/`, sin duplicar
generadores). La fantasía cambia de "lanzarse con mecanismos" (FD-320) a **trepar la
estructura**: la ruta principal es la subida por scaffold más larga y segura; los
atajos (~5 por semilla) son chunks curados hechos a mano (máquinas reconvertidas en
chunks estándar, cintas en tres roles, puertas de gloo y láser) que reducen la subida
a cambio de peligro.

**Narrativa ambiental:** sin texto ni hints de teclas en el juego. Toda la
información es diegética: luces, efectos y la silueta de la cima.

**Semilla por partida:** se guarda en el save y en el replay; Continuar mantiene la
misma semilla. Determinismo estricto: `RandomNumberGenerator` sembrado, nada de
`randf` global ni `Engine.get_frames_drawn()` en lógica de estado.

**Ciclo de protocolo global:** tiempo = ventanas locales por peligro SINCRONIZADAS
con un ciclo de la bahía (calma/aviso/peligro) visible en las luces de toda la sala.
Se generaliza el ciclo de `LabyrinthSection.gd` (FD-320+), no se reinventa.

**Perf:** streaming por cercanía de chunks; solo se muestran las áreas vecinas. El
activador genérico por cercanía lo construye otro worker (src-51) en
`core_v2/props/machines` o `core_v2/levels/machines`; este FD deja un punto de
enganche claro (§8) y no lo duplica.

---

## 2. Enmienda a FD-320 (alcance del rediseño)

FD-320 definió la bahía como sandbox de máquinas (balancín, péndulo, catapulta, brazo
centrífugo) con sentencia vertical y física de lanzamiento. Este rediseño conserva la
física y las máquinas como **chunks curados de atajo** (rotor, péndulo, válvula…),
pero reorganiza el nivel alrededor del pozo vertical y la trepada de scaffold. Lo que
sigue vigente de FD-320: `MachineLevel` (formato JSON), `MachinePart`/`MachineHinge`,
contratos de `machine-launch.md` (hub) y el recorrido de regreso RingHub. Lo que
cambia: el layout plano de estaciones se reemplaza por el pozo radial; la fantasía
central es trepar, no lanzarse.

---

## 3. CONTRATO DE CHUNK

### 3.1 Geometría radial y proyección polar (compatible WFC)

- El pozo es un cilindro con eje vertical (Y). La grilla del generador MST/WFC se
  reinterpreta así (mismo principio que FD-052 v3 §2 y `ScaffoldOrbit`):
  - **Grid X → ángulo θ** (circunferencial). `wrap_x = true` → el anillo cierra.
  - **Grid Y → radio r** = `inner_radius + grid_y * ring_step`.
  - **base_height → altitud Y** (vertical). `HEIGHT_STEP` del generador = paso
    vertical nominal.
- Transform por celda:
  ```gdscript
  var angle := TAU * float(cx) / float(sectors)
  var radius := inner_radius + float(cy) * ring_step
  var pos := Vector3(radius * cos(angle), base_height, radius * sin(angle))
  var tangent := Vector3(-sin(angle), 0.0, cos(angle))
  var radial := Vector3(cos(angle), 0.0, sin(angle))
  basis = Basis(tangent, Vector3.UP, radial)
  instance.transform = Transform(basis, pos)
  instance.rotate_object_local(Vector3.UP, deg2rad(-variant.rotation))
  ```
- Convención de ejes: Z local = forward navegable (radial); Y local = up; X local =
  tangente. No invertir Z (contrato ODI-001 de FD-052 v3).
- **Módulos:** los 9 de `core_v2/props/scaffold/` (`ScaffoldWalkway/Railing/Platform/
  Stairs/Curve/Gap/Cross/TJunction/End`). Se aplican los mismos setters que
  `LabyrinthSection._instance_grid` (dims de lane, rails en todos los bordes,
  openings en lados conectados, `front/back_height_offset` para rampas, y
  `support_base_local_y` para que las patas apoyen en y=0).
- **Sockets/bordes radiales:** cada celda expone sus 4 conexiones N/E/S/O (o
  angular/radial). La costura entre chunks vecinos es una celda `W` plana calculada
  con hash estable de la coordenada del borde (mismo patrón que
  `MachineBayLabyrinthStreamer._fixed_border_tiles`): dos chunks contiguos derivan el
  mismo índice y la misma altura, garantizando continuidad.
- **extra_cycles ≥ 2** → caminos alternos garantizados (ciclos en el grafo conexo).

### 3.2 Alturas de nivel

- Tres niveles por banda de altitud:
  - **Planta:** `y ∈ [0, 4)` — entrada, piso de caída, inicio de la subida.
  - **Entrepiso:** `y ∈ [4, 8)` — plataformas intermedias y atajos.
  - **Cima:** `y ∈ [8, 12+]` — sala de control + salida.
- `nivel_de(base_height)` clasifica cada celda. La cima es la celda de mayor altura
  (desempate por menor índice angular); su baliza emisiva es visible desde la planta
  (orienta). La entrada es una costura fija a altura 0.
- El piso de la planta es un anillo estático debajo del pozo: caer desde cualquier
  nivel aterriza en la ruta principal (sin muerte ni checkpoint salvo vacío real).

### 3.3 Tipos de atajo (~5 por semilla)

Chunks curados (autoría a mano, instanciados según semilla en posiciones fijas del
anillo):

| Chunk | Rol | Implementación |
|---|---|---|
| **Cinta-transporte** | atajo rápido y seguro | `Conveyor.tscn` puenteando un hueco (empuja al jugador entre plataformas) |
| **Cinta-arrastre** | peligro temporal | `Conveyor.tscn`/`ConveyorCarrousel.tscn` que arrastra hacia el vacío si se activa en peligro |
| **Cinta-cajas** | ayuda a trepar | `Conveyor.tscn` trayendo `PushableBoxV2` (cajas apilables) |
| **Puerta gloo** | atajo por construcción | `GlooSpan` — requiere N blobs de gloo pegados para habilitar la pasarela |
| **Puerta láser** | atajo por corte | `LaserGate` — panel que bloquea el paso; el láser lo corta (acumula `laser_hit`) |

Interfaz común: cada atajo se registra en el pozo con `id`, `tipo`, `nivel` y
`estado` serializable.

### 3.4 Interfaz de peligro con fase del ciclo global

- Ciclo global `BayProtocolCycle` (generalización del protocolo de
  `LabyrinthSection.gd`): fases `SAFE` → `WARNING` → `DANGER`, con duraciones
  configurables y avance determinista por acumulación de `_elapsed` en
  `_physics_process`.
- Cada peligro declara una **ventana local** dentro de `DANGER` (offset + duración).
  Fuera de su ventana está inerte visualmente (apagado) y físicamente (sin daño).
- **Luz global:** cada fase pinta todas las luces de la sala (verde estable /
  ámbar parpadeante / rojo,frío). La ruta principal usa luz cálida estable; los
  atajos usan franjas de peligro y luz fría o parpadeante.
- Física de peligros siempre en `_physics_process`.

### 3.5 Estado serializable (replay + save)

- El pozo es miembro de `replay_sync` e implementa `restore_snapshot(data)`.
- `get_state() -> Dictionary` expone: `seed`, `extra_cycles`, `niveles`, y el estado
  de cada atajo (progreso de corte de láser, blobs de gloo presentes, cintas
  activas/desactivadas). Todo reproducible desde `seed` + acumulación de `_elapsed`.
- **Semilla por partida:** `set_seed_from_save(seed)` se invoca al cargar; el save
  guarda la semilla y el replay la reproduce. Sin `randomize()` en runtime.
- **Ciclo:** `BayProtocolCycle` también es `replay_sync`: restaura `_elapsed` y
  `_phase` (las fases son derivables del tiempo, pero restaurar evita drift).

---

## 4. Plan de tareas por etapas

| Etapa | Contenido | Entregable |
|---|---|---|
| A | FD (este archivo), contrato de chunk, tabla de reconciliación | FD aprobado |
| B | `BayProtocolCycle.gd` (ciclo generalizado + luces) | componente reusable |
| C | `BayVerticalWell.gd` (generador radial sembrado + instanciación + streaming por cercanía + gancho para activador de src-51) | pozo generado |
| D | Atajos: `ShortcutConveyor.gd`, `GlooSpan.gd`, `LaserGate.gd` | 2+ atajos de tipos distintos |
| E | Escena `BayVertical.tscn` (Pilot, spawn, ambiente, baliza de cima, piso de caída) | greybox jugable |
| F | Tests GdUnit: determinismo (misma semilla → mismo layout), conectividad (cima alcanzable), ciclo/fases, streaming | suite nueva en verde |
| G | Enriquecer atajos a ~5 por semilla, pulido visual, medición low-end | iteración post-greybox |

---

## 5. TABLA DE RECONCILIACIÓN DE FDs CRUZADOS

| FD | Qué aporta | En este contrato | Estado |
|---|---|---|---|
| FD-320 (bahía actual) | MachineLevel JSON, MachinePart/MachineHinge, lanzamiento inercial, retorno RingHub | Se mantiene como cimiento físico/formato; el layout plano de estaciones se reemplaza por el pozo. Las 4 estaciones pasan a ser chunks curados de atajo | **Parcialmente fusionado** (cimientos vigentes; layout superado) |
| FD-050 (scaffold WFC) | `ScaffoldWFCGenerator`, 9 módulos, costuras, rails/openings | Generador + módulos reutilizados tal cual; proyección polar nueva | **Fusionado** (se reusa, no se duplica) |
| FD-050.1 (rails+openings) | Invariante rails siempre presentes, openings en conexiones | Se aplica la invariante al instanciar chunks | **Fusionado** (contrato de instanciación) |
| FD-050.2 (threaded/streaming) | Worker threaded, instanciación progresiva, streaming infinito | El streaming por cercanía de este FD sigue el patrón; se deja gancho para el activador genérico de src-51 | **Vigente parcial** (patrón reusado; thread opcional en greybox) |
| FD-314 (ringhub scaffold streaming) | Streaming de superestructura por chunks + `DeferredSceneChunk` | Se reusa el patrón de chunk por sector + colisiones normalizadas (Prop) | **Fusionado** (patrón) |
| FD-037 (campo infinito) | Scaffold procedural visual con exclusiones | No se fusiona: el pozo es jugable y finito; los dominios difieren | **Obsoleto para esta feature** (sigue vigente para su propio alcance) |
| FD-052 / v2 (MST polar duct maze) | Proyección polar `grid_to_world`, ejes ODI-001, layers Prop para cámara passthrough | Se adopta la proyección polar y la convención de ejes; el pozo usa scaffold, no ductos translúcidos | **Fusionado** (convención y proyección) |
| FD-053 (airlock manager) | Transiciones seamless y chamber persistente | La salida de la cima es un marcador + punto de enganche para transición (no se implementa el manager acá) | **Vigente** (dependencia futura) |
| FD-035 (conveyor/carrousel) | Conveyor con occupancy, luces, carrousel | Cintas reutilizadas en 3 roles (transporte/arrastre/cajas) | **Fusionado** |
| FD-045 (gas) | Zonas de gas con asfixia | No entra en el greybox; queda como candidato de peligro de nivel (mezcla curada) para G | **Vigente** (opcional en etapa G) |
| FD-051 (fuego) | Sistema de fuego + banda visual | Ídem gas: candidato de peligro curado de nivel | **Vigente** (opcional en etapa G) |
| FD-244 (multitool) | Láser + gloo gun (API pública: `laser_hit`, grupo `gloo_blob`) | Las puertas gloo/láser usan SOLO la API pública de `MultiToolV2` y sus proyectiles; toleran cambios (src-50 rehace controles) | **Fusionado** (interfaz de gates) |
| FD-298 (linterna) | Batería/toggle en OdiseaOS | No afecta este diseño; la luz de sala es diegética independiente | **Vigente** (sin interacción) |

---

## 6. Verificación

1. `./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_bay_vertical_gd` — suite nueva en verde.
2. Determinismo: misma semilla → mismo layout (deep-equal); semillas distintas → layouts distintos.
3. Conectividad: BFS desde la entrada hasta la cima sobre el grafo de conexiones del layout (ruta principal).
4. Ciclo: fases SAFE/WARNING/DANGER avanzan de forma determinista con el tiempo; los peligros se activan solo en su ventana de DANGER.
5. Streaming: con `enable_streaming=true`, solo los chunks dentro del radio de carga se instancian; fuera del radio de descarga se liberan.
6. Capturas del greybox en `core_v2/levels/bay_vertical/` (máx. 2000 px) aprobadas por Sebastián.
7. Sin texto ni hints de teclas en el nivel; toda la información es diegética.

---

## 7. Archivos

### Nuevos (este FD)
- `docs/features/FD-322_bahia_vertical_radial.md` (este archivo)
- `core_v2/levels/bay_vertical/BayProtocolCycle.gd` — ciclo global generalizado
- `core_v2/levels/bay_vertical/BayVerticalWell.gd` — generador radial + instanciación + streaming + estado
- `core_v2/levels/bay_vertical/ShortcutConveyor.gd` — atajo de cinta (transporte/arrastre/cajas)
- `core_v2/levels/bay_vertical/GlooSpan.gd` — puerta de gloo
- `core_v2/levels/bay_vertical/LaserGate.gd` — puerta de láser
- `core_v2/levels/bay_vertical/BayVertical.tscn` — escena del greybox
- `core_v2/tests/test_bay_vertical.gd` — suite GdUnit (determinismo, conectividad, ciclo)
- `docs/agents/sessions/2026-11-14_bahia_vertical.md` — bitácora de la sesión

### No se tocan (jurisdicción de otros workers)
- `core_v2/levels/machines/*` y `core_v2/props/machines/*` (src-51: activador genérico)
- `core_v2/input|player|ui/*` (src-50: multitool y controles)
- FDs existentes y `docs/features/archive/*` (src-52: archivado)

---

## 8. Gancho para el activador genérico de src-51

El streaming de `BayVerticalWell` es deliberadamente mínimo y **local**: decide por
distancia qué chunks instanciar/liberar. Cuando el activador genérico por cercanía de
src-51 aterrice en `core_v2/props/machines` o `core_v2/levels/machines`, `BayVerticalWell`
debe delegar en él vía el método `_call_proximity_activator(player_pos, chunks)` (marcado
como punto de enganche en el código); mientras tanto, el método cae a la implementación
local. Se deja explícito en comentario `TODO(src-51)` para no duplicar lógica al mergear.
