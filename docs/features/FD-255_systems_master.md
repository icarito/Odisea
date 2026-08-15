# FD-255: Los 4 Sistemas de la Nave — Documento Maestro

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-15
**Children:** FD-256 (Criocoolant), FD-257 (Plasma), FD-258 (Atmósfera), FD-259 (Energía auxiliar)

## Principio rector

La Odisea es una nave colonizadora de 8 km cuyo único trabajo es **mantener viva a la
humanidad en criogenia**. Cada elemento industrial es un *órgano con función*, no decorado.
Si cada prop tiene una tarea real, el layout se lee solo: una válvula de coolant pertenece
junto a los criopods, una conducción de plasma junto a la energía, una esclusa junto a la
presión.

> **Regla de legibilidad:** un peligro ambiental solo es legible si el jugador ve su
> *fuente funcional* antes de sufrirlo. Leer una sala = ver qué circuito domina el espacio.

## Los 4 sistemas como lenguaje de diseño

| Sistema | Color | Función | Vive junto a | Fallo | Aviso | Liberación |
|---|---|---|---|---|---|---|
| **Criocoolant** | cian | Refrigerante que congela los pods | criopods | Fuga de gas frío → niebla (ciega, no daña) | condensación → gotas → nube | Sellar válvula |
| **Plasma** | ámbar | Energía de alta temperatura | conducciones de energía | Fuga de plasma → barrera de daño | tubería brilla → zumbido → chorro | Redirigir flujo |
| **Atmósfera** | blanco/rojo | Presión y aire del sector | esclusas y compuertas | Sobrepresión → explosión ambiental | parpadeo → chispa → boom | Purgar/igualar presión |
| **Energía auxiliar** | verde | Respaldo de emergencia | consolas, levers, salas B | Sin energía → puertas selladas | lectura OD-02 parpadea → bloqueo | Accionar lever/secuencia |

El color dice *qué falla* antes de que dañe; el fallo dice *qué restaurar*. Y cada
liberación es **reordenar ese órgano** — de ahí sale "ganar = recuperar control".

## Mapeo a assets existentes

| Sistema | Assets ya existentes (reutilizar) | Integración pendiente |
|---|---|---|
| Criocoolant | `core_v2/systems/ice/` (IceLevel, IceVisualBand), `props/pipe/` (PipeValve, PipeSection/Corner/Tee), `systems/gas/` (GasArea3D para niebla) | Renombrar/integrar `visual/plasma_exhaust/PlasmaExhaust_D` como **CryoVent** |
| Plasma | `props/exhaust/PlasmaExhaust.tscn` (nozzle con IDLE/FLARE/SURGE), `systems/fire/` (FireSystem/FireEmitter), `systems/gas/` (gas inflamable) | Mantener `props/exhaust/PlasmaExhaust` como plasma real |
| Atmósfera | `systems/AirlockPool.gd`, `props/doors/AirlockChamber.tscn`, `IrisDoorV2.tscn`, `VerticalDoor.tscn` | — |
| Energía auxiliar | `systems/circuit/` (LogicCircuitManager, CircuitGraphResource, CircuitCable destructible, CircuitTerminalBridge), `InteractableBaseV2` (levers, terminales) | — |

## Integración y nombres coherentes de los efectos

Hoy hay dos cosas con nombre casi idéntico que cumplen roles distintos:

- `core_v2/visual/plasma_exhaust/PlasmaExhaust_D.tscn` — pluma **genérica tintable**
  (capa A = cáscara volumétrica + capa C = partículas, con `core_color`/`hot_color`
  compartidos). Por defecto es azul. **Es el crioenfriador**: renombrar a `CryoVent`.
- `core_v2/props/exhaust/PlasmaExhaust.tscn` — nozzle de reactor con máquina de estados
  (IDLE/FLARE/SURGE) y ciclo de color. **Es el plasma real**: queda como está.

Cada FD hijo detalla el renombre/integración que le toca. No se borra nada; se aclaran
nombres y se asigna cada efecto a un sistema.

## Estructura de cada FD hijo (mantener simple)

Cada FD-25x describe UN sistema con el mismo esqueleto mínimo:
1. Función y lugar físico
2. Lenguaje visual (color + señal)
3. Fallo y aviso (patrón legible)
4. Liberación (mini-game de restaurar)
5. Assets a reutilizar + archivos a crear/renombrar
6. Verificación

## Scope y orden

- Cada sistema es independiente y se puede construir/testear aislado (F6 por escena).
- Los mini-games de liberación reutilizan `InteractableBaseV2` y `LogicCircuitManager`;
  **no** se inventa un sistema de interacción nuevo.
- Orden acordado (ver `## Decisiones`): **Criocoolant y Energía auxiliar en paralelo**, luego
  Plasma, luego Atmósfera.

**Fuera de alcance de esta tanda:** las *Duct Sections* componibles y optimizadas. La geometría
de ductos ya tiene dos caminos (`core_v2/props/tube/` a mano y `DuctMazeStreamer` +
`DuctArcBuilder` procedural, FD-052); unificarlos es un FD aparte. Acá los sistemas se
construyen en una escena taller, no en ductos.

---

## Inventario de assets

Verificado en disco el 2026-08-15. Lo que el FD afirmaba y lo que hay:

| Asset | Estado | Nota |
|---|---|---|
| `core_v2/props/pipe/` (PipeSection/Corner/Tee, `PipeValve.gd`) | EXISTE | `PipeValve` hereda `InteractableBaseV2`, con snapshot y señal `valve_state_changed`. **Cero usos en escenas de nivel.** |
| `core_v2/systems/gas/GasArea3D.gd` (429 líneas) | EXISTE | Grid de densidad, combustión, empuje y daño al jugador. Usado en `Dome_Crio.tscn`. |
| `core_v2/systems/gas/GasParticleManager.gd` (617 líneas) | EXISTE | MultiMesh + flipbook, pool adaptativo en móvil, determinista y con snapshot. |
| `core_v2/props/emitters/LeakEmitter.gd` | EXISTE-OTRO-ROL | Es **decorativo**: `_process`, `rand_range` en los burst, sin `replay_sync` ni snapshot. Sirve para el *aviso*, no para el fallo con consecuencia. Cero usos en niveles. |
| `core_v2/props/emitters/FireEmitter.gd` / `FrostEmitter.gd` | EXISTE | Ambos en `replay_sync` con snapshot. `FrostEmitter` está en `Dome_Intro.tscn`. Ver riesgo R2. |
| `core_v2/systems/circuit/` (LogicCircuitManager 586 líneas, CircuitGraphResource, CircuitCable, CircuitTerminalBridge, CircuitUINode) | EXISTE | Lógica por ticks en `_physics_process`, compuertas AND/OR/XOR/NOT/DELAY, cables destructibles. **Cero usos en escenas de nivel**: solo `circuit/examples/CircuitExample.tscn`. |
| `addons/odyssey_circuit_editor/` (CircuitBoard, plugin) | EXISTE-OTRO-ROL | El plugin está en el repo pero **no figura en `enabled=` de `project.godot`**: hoy no hay editor. Su UI está incompleta (agregar nodo, inspector) según `docs/interaction/IMPLEMENTATION_PLAN.md`. |
| `core_v2/systems/ice/` (IceLevel, IceVisualBand, IceObjectFreezer) | EXISTE | `IceLevel` en `Dome_Intro.tscn`, con snapshot. |
| `core_v2/systems/fire/` (FireSystem, FireVisualBand, FireDestructible) | EXISTE | `FireSystem` en `Dome_Intro_Fire.tscn`, determinista y con snapshot. |
| `core_v2/props/exhaust/PlasmaExhaust.tscn` (nozzle IDLE/FLARE/SURGE) | EXISTE | Es el plasma real. Único referenciador externo: `TestZeroGravity.tscn`. |
| `core_v2/visual/plasma_exhaust/PlasmaExhaust_{A..E}` + `PlasmaExhaustBase.gd` | EXISTE-OTRO-ROL | Pluma tintable genérica: es el CryoVent. **Único referenciador externo: `TestZeroGravity.tscn` (6 `ext_resource`)** ⇒ el renombre es barato. |
| `core_v2/systems/AirlockPool.gd` | EXISTE | — |
| `core_v2/props/doors/` (AirlockChamber, IrisDoorV2, VerticalDoor, HeavyBlastDoor, ElevatorDoor) | EXISTE | El FD-258 citaba `props/AirlockChamber.tscn`; la ruta real es `props/doors/AirlockChamber.tscn`. |
| `docs/interaction/CIRCUIT_SYSTEM.md` + 7 docs más | EXISTE | Contrato, migración, validación de props e integración con terminales. |
| `core_v2/tests/TestScenePropZoo.tscn` | EXISTE | Auto-descubre props; referencia útil para armar la escena taller. |

Lectura corta: **no falta casi nada; falta conectarlo**. Los tres subsistemas que este FD
quiere usar (pipes, circuitos, gas) están implementados y no se usan en ninguna escena de nivel.

---

## Riesgos y contratos

| # | Riesgo | Evidencia | Mitigación |
|---|---|---|---|
| R1 | **El pegamento no sobrevive un replay.** `LogicCircuitManager` corre por ticks en `_physics_process` (bien) pero **no está en `replay_sync` ni implementa `get_snapshot`/`restore_snapshot`**. Su `anna_get_snapshot()` es para debug, no para el contrato. Si las puertas dependen del circuito, el replay diverge. | `LogicCircuitManager.gd` — sin `add_to_group("replay_sync")` | Tarea T1, bloquea todo lo del sistema de energía. |
| R2 | **`FireEmitter` aplica daño en `_process`.** Emite `damage_tick` desde `_process(delta)`, o sea daño dependiente de FPS: viola `AGENTS.md` §5.3. `FrostEmitter` ya hace el daño en `_physics_process`. | `FireEmitter.gd:31-46` | Tarea T5: mover a `_physics_process`. |
| R3 | **`GasArea3D` no restaura estado.** Corre en `_physics_process` (bien) pero no está en `replay_sync` ni tiene snapshot: densidad, celdas ardiendo y cuerpos adentro se pierden. La niebla de criocoolant y la barrera de plasma quedan fuera del contrato. | `GasArea3D.gd` | Tarea T4. |
| R4 | **Los emisores usan `randf` para posicionar partículas** que entran al pool de `GasParticleManager`, y ese pool **sí** se snapshotea. Ruido no reproducible tocando estado sincronizado. | `FireEmitter.gd:48-56`, `LeakEmitter.gd:42,132,185` | Confirmar en T5 que el ruido queda solo en lo visual, o derivarlo de un contador determinista (`_hashed_unit`, como ya hace `FrostEmitter`). |
| R5 | **Presupuesto de render.** Cada estación suma un `GasParticleManager` (MultiMesh + pool) más luces de color. Cuatro estaciones en una escena es el caso peor. | Perf histórica: las luces realtime fueron el 84% de draw calls en `Dome_Intro` | Medir con `VisualServer.get_render_info` en la escena taller antes de integrar a un domo. En 3.6 usar `INFO_OBJECTS_IN_FRAME`, no `INFO_*_DRAWS_IN_FRAME`. |
| R6 | **GLES2.** El proyecto es GLES2: partículas por `CPUParticles` o por el `GasParticleManager` (MultiMesh), nunca el nodo `Particles`. Sin `SCREEN_TEXTURE` en efectos que deban verse en Android. | `AGENTS.md` §11.7 | Regla para todo brief de esta familia. |
| R7 | **Props que se apagan solos.** `InteractableBaseV2` corta `_physics_process` en reposo (FD-224); un aviso con animación por tiempo (parpadeo del manómetro, pulso del nozzle) se congela salvo `_wants_continuous_step()`. | FD-224 | Regla para todo brief de esta familia. |
| R8 | **`project.godot` está modificado en el working tree** y es archivo compartido y conflictivo. La tarea que habilita el plugin lo toca. | `git status` | T2 la hace una sola tarea, local, nunca Jules. |
| R9 | **Duplicado documental:** FD-028 "Plasma Leak Obstacle" (Planned) cubre lo mismo que FD-257. Además FD-255..259 no figuran en `FEATURE_INDEX.md`, y `FD-045_gas_simulation.md` se titula "FD-043" adentro. | `FEATURE_INDEX.md:93` | Tarea T7 (limpieza documental). |

---

## Decisiones

Acordadas con Sebastián el 2026-08-15:

1. **Pegamento = `LogicCircuitManager`.** No se crea una base `ShipSystemV2`. Cada sistema
   expone sus interactuables (`PipeValve`, lever, dial) y el grafo de circuito conecta señal →
   puerta/efecto. A cambio, hay que darle determinismo al manager (T1).
2. **Se construye en una escena taller**, `core_v2/tests/TestShipSystems.tscn`, con una estación
   por sistema. No se tocan escenas de nivel en esta tanda. Cada estación es una **sub-escena
   propia** (`core_v2/tests/stations/*.tscn`) instanciada en el taller: así dos sistemas en
   paralelo nunca editan el mismo archivo.
3. **El editor de circuitos se habilita tal cual** (una línea en `project.godot`) y se usa hasta
   donde llegue. Completar su UI (agregar nodo, inspector) es un FD aparte, solo si estorba.
4. **Orden: Criocoolant y Energía auxiliar en paralelo**, después Plasma, después Atmósfera.
   Criocoolant porque todo su material existe y valida el patrón completo con el menor riesgo;
   Energía porque ejercita el circuito, que es el pegamento del resto.
5. **Duct Sections componibles: fuera de alcance.** Interesan los sistemas individuales.
5b. **CryoVent: solo la opción D.** De las cinco variantes de la pluma, la elegida es la D
   (cáscara volumétrica + partículas). B y E quedan archivadas en `visual/cryo_vent/options/`;
   A y C no se archivan porque son las dos capas que D compone. Paleta cian y `brightness` 2.6.
5c. **Escena taller aprobada** (2026-08-15): piso de 44 m, pads de 7×7 separados 18 m. La escala
   y las distancias funcionan; no hace falta acercar las estaciones.
6. **Reparto por cómo se verifica, no por tamaño.** Jules recibe lógica sustancial (máquinas de
   estado, determinismo, snapshots, tests) y corre hasta 3 sesiones en paralelo. Todo lo visual
   —props, materiales, escala, luz, calibración de efectos— se hace local con `test_prop.sh` y
   capturas, porque un prop no está listo cuando compila sino cuando se ve bien.

---

## Plan de ejecución

Dos carriles que corren a la vez:

- **Carril lógica (Jules, 3 sesiones en paralelo).** Máquinas de estado, determinismo, snapshots
  y tests. Se juzga leyendo el diff y corriendo la suite.
- **Carril visual (local, Sonnet/Opus con capturas).** Props, materiales, escala, luz,
  composición de las estaciones, calibración de la pluma y la niebla. Lazo corto:
  editar → `test_prop.sh` → mirar → ajustar, con Sebastián opinando.

Los sistemas salen deterministas por un lado; cuando hay base coherente, se les pone la cara
encima y se itera en vivo.

### Ola 1 — Jules (paralelas, archivos disjuntos)

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| J1 | **Determinismo del pegamento.** `LogicCircuitManager` → grupo `replay_sync` + `get_snapshot`/`restore_snapshot` completos (colas de entrada/salida, estado de nodos, delays pendientes de las compuertas DELAY) + test de replay que arma un grafo, lo corre N ticks, restaura y compara | JULES | `core_v2/systems/circuit/LogicCircuitManager.gd`, `core_v2/tests/test_circuit_determinism.gd` (nuevo) | test nuevo pasa; `test_determinism_v2.gd` sigue pasando | — | hecho · PR #283 mergeado |
| J2 | **Peligros deterministas.** `GasArea3D` → `replay_sync` + snapshot (grid de densidad, celdas ardiendo, cuerpos adentro). `FireEmitter` → spawn y `damage_tick` de `_process` a `_physics_process`, ruido de posición derivado de contador (patrón `_hashed_unit` de `FrostEmitter`). `LeakEmitter` → comentario de cabecera declarándolo decorativo | JULES | `core_v2/systems/gas/GasArea3D.gd`, `core_v2/props/emitters/FireEmitter.gd`, `core_v2/props/emitters/LeakEmitter.gd`, test nuevo | daño independiente de FPS; snapshot/restore reproduce la nube | — | hecho · 5 tests pasando |
| J3 | **Sistema Criocoolant (lógica).** `core_v2/systems/cryo/CoolantLeak.gd` nuevo: máquina de estados SANO → AVISO → FALLO → LIBERADO, señales por transición, `set_active` desde un `PipeValve`, snapshot/restore, y API para que el visual se cuelgue (`get_state()`, `state_changed`). Sin geometría ni materiales | JULES | `core_v2/systems/cryo/**` (nuevo), test nuevo | la secuencia completa corre headless y es determinista; cero nodos visuales creados | — | hecho · PR #282 mergeado |

### Carril visual y de entorno (local, en paralelo a la Ola 1)

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| L1 | Habilitar `addons/odyssey_circuit_editor/plugin.cfg` en `project.godot`; abrir el dock y ver hasta dónde llega | LOCAL | `project.godot` | el editor levanta y muestra "Circuit Board" al seleccionar un `LogicCircuitManager` | — | hecho (falta confirmación visual del dock) |
| L2 | Renombrar `visual/plasma_exhaust/` → `visual/cryo_vent/` (`PlasmaExhaust_{A..E}` → `CryoVent_{A..E}`, `PlasmaExhaustBase` → `CryoVentBase`, 6 `ext_resource` de `TestZeroGravity.tscn`) **y calibrar la pluma en cian**: color, escala, densidad | LOCAL | `core_v2/visual/plasma_exhaust/**` → `core_v2/visual/cryo_vent/**`, `core_v2/tests/TestZeroGravity.tscn` | sin refs rotas; capturas de la pluma cian aprobadas por Sebastián | — | hecho · opción D única, B/E en `options/` |
| L3 | Escena taller `TestShipSystems.tscn`: piso, luz, spawn y cuatro anclas (una por estación). Cada estación será una sub-escena instanciada | LOCAL | `core_v2/tests/TestShipSystems.tscn` (nuevo) | abre con F6; escala y distancias validadas caminando | — | hecho · aprobado 2026-08-15 |
| L4 | Estación Criocoolant (visual): `PipeValve` + tubería + radiador + pluma `CryoVent_D` + volumen de niebla, colgados de la lógica de J3 | LOCAL | `core_v2/tests/stations/CryoStation.tscn` (nuevo) | capturas aprobadas; la sala se lee como "acá vive el coolant" | J3, L2, L3 | pendiente |
| L5 | Estación Energía auxiliar (visual): lever, panel OD-02 con parpadeo, `HeavyBlastDoor`, cables visibles | LOCAL | `core_v2/tests/stations/AuxPowerStation.tscn` (nuevo) | capturas aprobadas; se lee "puerta sellada por falta de energía" | J1, L1, L3 | en curso · subagente |
| L6 | Limpieza documental: FD-028 → superseded por FD-257; alta de FD-255..259 en `FEATURE_INDEX.md`; corregir el título interno de `FD-045_gas_simulation.md` | LOCAL | `docs/features/**` | el índice refleja la familia; no quedan dos FDs para la fuga de plasma | — | hecho |

### Ola 2 — Jules (al liberarse las sesiones de la Ola 1)

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| J4 | **Sistema Energía auxiliar (lógica).** `AuxPowerBus` + `SealedDoorLock` + grafo de ejemplo de la secuencia de paneles | JULES | `core_v2/systems/auxpower/**` (nuevo), `core_v2/systems/circuit/examples/**` | sin lever la puerta no abre; con lever abre; sobrevive snapshot/restore | J1 | en curso · jules `731758851250298961` |
| J5 | **Plasma (lógica).** `PlasmaConduit` (aviso → chorro de daño) + `PlasmaRoute` (puzzle de redirección con válvulas) | JULES | `core_v2/systems/plasma/**` (nuevo) | el aviso precede al daño; redirigir apaga la barrera; determinista | J2 | en curso · jules `4636087135113676369` |
| J6 | **Atmósfera (lógica).** `PressureSection` (parpadeo → chispa → boom) + `PurgeDial` (mini-game de sintonía) | JULES | `core_v2/systems/atmosphere/**` (nuevo) | `blowout` se emite una sola vez; purgar estabiliza; determinista | J2 | en curso · jules `17557628447042986994` |

### Checkpoints humanos

| # | Tarea | Ejecutor | Depende de | Estado |
|---|---|---|---|---|
| H1 | Balance de niebla: densidad, cuánto ciega, tiempo de disipación | HUMANO | L4 | pendiente |
| H2 | Legibilidad de energía: ¿se entiende sin texto que hay que restaurarla? | HUMANO | L5 | pendiente |

Reglas de corte aplicadas: ninguna tarea de Jules toca escenas (`.tscn`), `project.godot` ni
archivos de otra sesión; J3 **consume** la API de `GasArea3D` mientras J2 lo edita, sin
modificarlo; las estaciones son sub-escenas distintas, así que el carril visual avanza sin
chocar consigo mismo.

---

## Checkpoints en vivo

1. **Después de L3** — recorrer la escena taller vacía: escala, distancias, si se llega
   caminando de una estación a otra sin aburrirse.
2. **Durante L2 y L4** — la pluma cian y la niebla se calibran mirando capturas, no a ciegas.
3. **Después de L4** — el patrón criocoolant completo: ¿la condensación avisa a tiempo?, ¿la
   niebla ciega lo justo sin frustrar?, ¿cerrar la válvula se siente como un respiro?
4. **Después de L5** — el patrón energía: ¿se lee que la puerta está sellada por falta de
   energía y no por estar rota?
4. **Antes de integrar a un domo** — medir draw calls de la escena taller con las cuatro
   estaciones activas (R5) y comparar contra el presupuesto de `Dome_Intro`.

Cada ajuste que salga de estos checkpoints se anota en `## Decisiones` con fecha.

### Falso positivo registrado (2026-08-15)

Durante el desarrollo de la estación de criocoolant se persiguió durante horas un supuesto bug:
la `PipeValve` cambiaba de estado sola y sellaba la fuga. Se descartaron uno por uno la conexión
de señales, el culling de FD-224, el auto-wiring, la carrera Menu→escena y el caché de objetivo
del `PlayerControllerV2`.

**No era un bug.** Era entrada real de teclado llegando a la ventana headful que quedó abierta en
el escritorio: alguien caminando por el taller y pulsando la tecla de interacción. La prueba que
lo cerró: la misma escena en `--headless`, con el jugador pegado a la válvula, 30 segundos sin un
solo cambio de estado ni un milímetro de desplazamiento.

**Regla que sale de acá:** un comportamiento "espontáneo" observado en una sesión headful no es
evidencia de nada hasta reproducirlo en `--headless`. La ventana con foco es un jugador más.
