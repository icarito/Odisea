# Transit-Run · Fase 1 / W2 — Mapa de bloqueos del avance (auditoría SOLO LECTURA)

**Fecha:** 2026-11-15
**Sesión:** `ao/transit-run-fase-2/root` (worktree `src-60`)
**Naturaleza:** auditoría de solo lectura. No se modificó código ni escenas. Tests: ninguno nuevo;
no se corrió la suite completa.
**Objetivo:** responder, con evidencia de código/test y no por inferencia, **qué bloquea hoy el
avance** en MachineBay (corredor), el laberinto/ruteo de MachineBay y el Domo de Introducción
(beats 1–8 + descenso al hangar), para convertirlos después en **Side Sockets** opcionales
(atajos, impulsores, cargas de tool, lore) dentro de la regla de oro: *la ruta principal nunca
queda bloqueada por puzles obligatorios*.

---

## 0. Nota de fuentes (dos documentos citados no existen como tales)

- **FD-322** se pidió como «bahía radial». No existe ningún archivo `FD-322*` en el repo. La
  única referencia viva a «FD-322» es el encabezado del test del ruteo no lineal
  (`core_v2/tests/test_machine_bay_maze_routing.gd:3`) y un comentario de código
  (`core_v2/levels/machines/MachineBayMazeRouting.gd:13`) que apunta a
  `docs/features/FD-322_ruteo_laberinto_no_lineal.md` — **también ausente**. El diseño del ruteo
  vive hoy en `core_v2/levels/machines/MACHINE_BAY_ROUTING.md`. En este mapa trato «FD-322» =
  ruteo del laberinto de la bahía (no lineal). Los tres documentos que sí se pidieron leer:
  `AGENTS.md`, `docs/features/FD-289_dome_systems_canon.md`, `docs/features/FD-320_bahia_de_maquinas.md`.
- La **«bahía radial»** de acceso (pasillo RingHub→bahía) sí existe como trabajo real, pero como
  sesión, no como FD: `docs/agents/sessions/2026-11-13_conexion_domo_bahia.md`
  (`RingHubBayConnector.tscn` + `BayAirlockTrigger.gd`).

**Leyenda de la columna «¿Obligatorio hoy?»**

- **OBLIGATORIO (código/test):** hay una condición en código o un test que lo prueba.
- **OBLIGATORIO (geometría):** el layout lo hace imprescindible hoy (hueco + KillFloor), pero no
  existe test que recorra la ruta completa sin usarlo. Se marca la base exacta.
- **OPCIONAL (código/test):** existe código/test que prueba que la ruta crítica funciona sin él.
- **NO BLOQUEA (implementación incompleta):** el diseño dice que debería condicionar, pero hoy no
  hay gate cableado.

---

## 1. MachineBay — corredor de estaciones (ruta crítica actual)

Escena: `core_v2/levels/machines/MachineBay.tscn` (instancia `Level` con `MachineLevel.gd`, layout
`core_v2/levels/machines/machine_bay.json`). Corredor central `x ∈ [-7, 7]`, de −Z (entrada,
z≈4.5) a +Z (salida, ExitPad z≈138). Debajo de todo el corredor: `KillFloor` en y=−18.
Los enlaces de layout son 1-based por línea del JSON.

| Elemento | Archivo:línea / nodo-ID | ¿Obligatorio hoy? | Qué lo desbloquea | Conversión a Side Socket (recompensa cinética) | Riesgo |
|---|---|---|---|---|---|
| **Entrada / piso de arranque** `EntryFloor` (top y=0) | `machine_bay.json:41`; spawn `MachineBay.tscn:71` (SpawnPointV2) | Es el punto de partida (no bloquea) | — | Punto de spawn del flow / marcador ANNA | Cambiar el spawn invalida capturas y `test_machine_bay_route` |
| **Estación 1 — Balancín** `SeesawLever`/`SeesawStrut`/`SeesawWeight` | `machine_bay.json:46-57`; links 53–57 | **OBLIGATORIO (geometría):** Ledge1 es un escalón de 2.5 m sobre EntryFloor (`Ledge1` pos `[0,1.25,17.1]` size `[10,2.5,11.8]` ⇒ top y=2.5, `machine_bay.json:59`; EntryFloor top y=0, `:41`). El balancín existe precisamente para salvarlo: apogeo >6.5 m (test `test_machine_bay.gd:162-171`). KillFloor abajo. | Accionar la palanca (o láser al retén) | **Impulsor de velocidad / rampa** para subir sin esperar los 2 s del contrapeso; la palanca queda como *boost* opcional | Replays de vuelo balístico en `PlayerMovementV2`; `test_machine_bay.gd:237-256` (reset) asume el retén |
| **Ledge1 / Dock1** | `machine_bay.json:59-65` | OBLIGATORIO (es la meseta de llegada) | — | Mirador / lore (cartel Odisea) | — |
| **Estación 2 — Péndulo** `PendulumLever`/`Gondola` | `machine_bay.json:66-84`; links 80–84 | **OBLIGATORIO (geometría):** Dock1 (top y=6.0, z 19.9–22.1, `:64`) → Dock2 (top y=5.6, z 36.2–39.2, `:86`): hueco sobre el vacío que la góndola cruza en ~14 m (FD-320; test `test_machine_bay.gd:174-187`, `max_z > 34`). | Accionar palanca / láser | **Impulsor** o **atajo al hangar**: el péndulo podría volverse el «lanzadera rápida» opcional | Igual que E1: balística + replay; test de péndulo asume el recorrido |
| **Dock2 / Ledge2** | `machine_bay.json:86-89` | OBLIGATORIO (meseta) | — | — | — |
| **Estación 3 — Catapulta** `LeverLight/Medium/Heavy` | `machine_bay.json:90-117`; links 107–116 | **OBLIGATORIO (geometría):** Ledge2 (top y=3.5, `:89`) → Ledge3 (top y=13.0, `:119`): ~9.5 m de subida. La catapulta da 11–33 m (test `test_machine_bay.gd:190-209`). | Elegir masa (palanca/láser) | **Impulsor variable** ya existente como «más masa = más altura»; el Side Socket puede *pre-cargar* la masa elegida | 4 casos balísticos en test; el rearme (`ResetStation3`) es estado de replay |
| **Ledge3** | `machine_bay.json:119-121` | OBLIGATORIO (meseta) | — | — | — |
| **Estación 4 — Brazo centrífugo** `CentrifugeLever`/`CentrifugeArm` | `machine_bay.json:122-133`; links 130–132 | **OBLIGATORIO (geometría):** Ledge3 (top y=13, z 52–64) → Station5Deck (top y=10, z 78–90, `:135`): ~14 m sobre el vacío. El brazo lanza 15 m (test `test_machine_bay.gd:212-234`). | Accionar palanca (o láser) y saltar en la tangente | **Atajo / Speed booster** (el rotor como «lanzadera de mantenimiento» opcional) | Replay sensible; test con salto temporizado |
| **Station5Deck + puente de fuego** `BridgeValveCut`/`DrawbridgeDeck`/`BridgeFlameL/R`/`TowerFlame1` | `machine_bay.json:135-159`; links 145–149 | **CONDICIONAL:** `DrawbridgeDeck` es estático y transitable (`:141`); las llamas (`FireEmitter`, `damage_per_tick` 15, `:143-144`) dañan pero **no cierran el paso**. La válvula (`BridgeValveCut`, `:140`) apaga el fuego → es **mitigación de daño, no un gate**. Evidencia: no hay bloqueador ligado a la válvula; los links (145–148) solo llaman `extinguish`. | Accionar `BridgeValveCut` | **Carga de tool / lore**: la válvula se vuelve opcional (el parkour por el puente es la ruta principal) | Los `FireEmitter` son deterministas; cambiar el daño afecta stress/telemetría |
| **Tower ramp → ExitPad** `TowerRamp`/`TowerAscendRamp` | `machine_bay.json:156-163` | OBLIGATORIO (única subida peatonal a ExitPad top y=22, `:161`) | — | **Atajo** por rampa/ascensor opcional | Geometría de rampa afecta el salto del brazo (E4) |
| **Válvula Maestra** `MasterFlowValve` | `machine_bay.json:166`; link `:175` → `complete_work_order` | **OBLIGATORIO para «cerrar» la Orden 0001**, no para el movimiento: `complete_work_order()` exige `MasterFlowValve.is_active` (`MachineLevel.gd:574-582`, si no muestra hint y retorna). | Abrir la válvula | **Lore / recompensa** (opcional): cerrar la Orden deja de ser requisito de avance | `test_machine_bay.gd:355-364` y `:280-307` asumen el cierre; SuitModel/objetivos |
| **OrderCompleteButton** | `machine_bay.json:173`; link `:183` | OPCIONAL (administrativo; mismo guard que la válvula, test `test_machine_bay.gd:280-307`) | — | Lore | — |
| **ReturnHubButton** → `return_to_ring_hub` | `machine_bay.json:174`; link `:184`; `MachineLevel.gd:610-628` | **OBLIGATORIO como «final» de la demo** (es el retorno al anillo); no bloquea el atravesar el nivel | `goto_scene(RingHub_Level)` con payload de retorno | Punto de salida / atajo al hub | Payload `ringhub_return_state` y `test_machine_bay_return` |
| **KillFloor** `KillZoneV2` | `machine_bay.json:186`; `core_v2/components/KillZoneV2.gd` | **OBLIGATORIO (hazard):** todo el corredor cuelga sobre y=−18; caer = respawn en checkpoint (test `test_machine_bay.gd:125-138`) | — | Se mantiene como «red de seguridad» del parkour | Cambiarlo altera los tests de respawn |
| **CheckZones** `CheckEntry`, `CheckLedge1/2/3`, `CheckStation5`, `CheckTowerBase`, `CheckExit` | `machine_bay.json:187-193`; `core_v2/components/CheckZoneV2.gd` | OPCIONALES (checkpoints, no gates; test `test_machine_bay.gd:67-159`) | Entrar al área | Puntos de respawn del flow (ideales para marcadores ANNA) | Saves/`CheckpointManager`; `test_machine_bay_route` los exige activos |
| **Triggers de voz Odisea** `VoiceEntry`, `VoiceLedge1/2/3`, `VoiceStation5`, `VoiceExit` | `machine_bay.json:195-225` | **NO BLOQUEA, pero congela input temporalmente:** `VoiceEntry` y `VoiceLedge1` disparan `@odisea focus_camera` (`:198`, `:206`). `ProgrammerHoloNPC.focus_camera` pide `latch_on_enter/latch_on_exit = true` (`core_v2/actors/ProgrammerHoloNPC.gd:340-359`) ⇒ `CinematicManager._engage_input_latch` (`core_v2/autoloads/CinematicManager.gd:1019-1020, 1254`) y `PlayerControllerV2` ignora input mientras dure (`core_v2/player/PlayerControllerV2.gd:1324`). | Se libera al terminar la duración del foco | Convertir en **lore no intrusivo**: subtítulo sin `focus_camera` para no cortar la corrida | Los beats narrativos dependen del foco; `test_machine_bay_route` afirma `is_input_latched() == false` (`:176`) |

> **Estado real del corredor:** el test público `test_machine_bay_route.gd` **solo cubre
> entrada → aproximación de E1** con input y zonas activas (`:213-273`). Los casos por estación
> `test_machine_bay.gd` **teletransportan** al piloto a cada estación y **desactivan** CheckZones y
> KillZones (`:35-40`). Por eso: E1–E4 son OBLIGATORIO **por geometría** (huecos + KillFloor),
> pero **no hay hoy un test que pruebe la travesía completa sin operar las máquinas**.

---

## 2. MachineBay — laberinto / ruteo no lineal («FD-322»)

Escena: `core_v2/levels/machines/MachineBay.tscn` (`LabyrinthSection` `:156`, `MachineBayLabyrinthStreamer`
`:161`, `MazeEntryBridge` `:163`, `MachineBayMazeRouting` `:209`). Director: `MachineBayMazeRouting.gd`
(tabla `JUNCTIONS` `:36-58`, `ROUTES` `:62-66`). El ruteo **no cruza el corredor central**
(`MACHINE_BAY_ROUTING.md:14-22, 39-44`).

| Elemento | Archivo:línea / nodo-ID | ¿Obligatorio hoy? | Qué lo desbloquea | Conversión a Side Socket | Riesgo |
|---|---|---|---|---|---|
| **`maze_entry`** (boca oeste, ~`(8.5,0,12)`) | `MachineBayMazeRouting.gd:37-43` (requirement `always`) | **OPCIONAL (test):** `test_machine_bay_maze_routing.gd:66` (siempre abierta); la ruta `corridor` está abierta sin ella (`:70-76`) | Nada (siempre) | Boca de un **atajo/laberinto de lore**: recompensa al completarlo | Entrada siempre abierta: el jugador puede perderse temprano |
| **`maze_exit`** (paso a Estación 2) → requiere `SeesawLever` (E1) | `MachineBayMazeRouting.gd:44-50`; test `:80-91` | **OPCIONAL (test):** es un atajo lateral entre E1 y E2; el corredor no lo necesita (`MACHINE_BAY_ROUTING.md:39-40`). **No permite saltear E1**: sin E1 la compuerta sigue cerrada (test `:86-87, 115-120`) | Completar Estación 1 (balancín) | **Atajo** que da un **impulsor/boost** al reincorporarse | El estado de la compuerta es función pura de `MachineLevel` (test `:109-120`) → cuidado con el determinismo de replays |
| **`field_link`** (campo streamed WFC) → requiere `PendulumLever` (E2) | `MachineBayMazeRouting.gd:51-57`; test `:88-91` | **OPCIONAL (test):** tercer tramo; el corredor sigue siendo la ruta crítica (`MACHINE_BAY_ROUTING.md:43-44`) | Completar Estación 2 (péndulo) | **Zona de lore / carga de tool** en el campo procedural | WFC determinista (`seed_base`); no introducir RNG runtime |
| **Compuertas `MazeRoutingGate`** (barrera física on/off) | `MazeRoutingGate.gd:53-72`; test de colisión `test_machine_bay_maze_routing.gd:150-165` | OPCIONAL (gatean solo los atajos) | Según requisito de cada enlace | Mismas compuertas, re-etiquetadas como «atajo» | `InteractableBaseV2` + grupo `replay_sync`: snapshot de `is_active/anim_progress` |

> **Conclusión del ruteo:** el laberinto **ya cumple** la regla de oro (no bloquea la ruta
> principal). La conversión a Side Socket es de **etiquetado y recompensa**, no de desbloqueo.
> Evidencia central: `MACHINE_BAY_ROUTING.md:39-48` + `test_machine_bay_maze_routing.gd:70-105`.
> Cuidado: hoy el atajo se abre al **accionar las palancas del corredor** (`item_active:SeesawLever`,
> `PendulumLever`), es decir la recompensa del Side Socket sigue dependiendo del puzle de máquina;
> si la máquina pasa a ser Side Socket, este requisito hay que redefinirlo.

---

## 3. Domo de Introducción — beats 1–8 y descenso al hangar

Escena raíz `core_v2/levels/interiors/Dome_Intro.tscn`: instancia `DomeMachineLevel`
(`:2355`, de `core_v2/systems/dome/DomeMachineLevel.tscn`) y `HangarDescent` (`:2362`, de
`core_v2/props/hangar/HangarDescent.tscn`). Director autoload `DomeSystemDirector`
(`core_v2/systems/dome/DomeSystemDirector.gd`), config `DomeEnvConfig_intro.tres`.

| Elemento | Archivo:línea / nodo-ID | ¿Obligatorio hoy? | Qué lo desbloquea | Conversión a Side Socket | Riesgo |
|---|---|---|---|---|---|
| **Beat 1 — Interruptor principal** `Energy/MasterSwitch` | `DomeMachineLevel.tscn:261-262`; handler `DomeNetworkWiring.gd:216-219` | **OBLIGATORIO:** primer accionar dispara `on_first_power_attempt` → beat 1 (arma la fuga de coolant). Sin beat 1 no arranca el ciclo (test `test_dome_timeline.gd:141-150`) | Accionar el interruptor | Convertirlo en **lore**: el domo arranca «ya encendido» y la fuga se revela por proximidad | Reordena el timeline; `test_dome_timeline`/`test_dome_systems` fijan la secuencia |
| **Beat 2 — Criocoolant** `Coolant/CoolantValve`, `LeakA`, `LeakB`, patches | `DomeMachineLevel.tscn:125-204`; wiring `DomeNetworkWiring.gd:195-204, 251-269` | **OBLIGATORIO (código/test):** red sana solo cuando **todas** las fugas están reparadas (`_all_leaks_repaired`, `:260-269`); 4/4 redes abren el blast door (test `:124-160`) | Cerrar válvula + parchear fugas (gloo) | **Carga de tool / lore**: reparar coolant como Side Socket que da una mejora | FD-266 (`LeakPatchPoint`); snapshots `_coolant_armed` |
| **Gating del bus** `require_coolant_for_bus` | `DomeNetworkWiring.gd:44-50, 222-233` | **OBLIGATORIO (test):** `BusSwitch` no restaura energía hasta el beat 2 (`enable_auxpower_lever`). Test explícito: `test_dome_timeline.gd:165-193` | Completar coolant (beat 2) | Side Socket: la energía podría ser opcional si el blast door deja de requerir 4/4 | Rompe el orden canónico del timeline |
| **Beat 3 — Energía** `Energy/BusSwitch`, `AuxPowerBus` | `DomeMachineLevel.tscn:257-265`; wiring `:222-227, 281-287` | **OBLIGATORIO (test):** red sana al restaurar el bus; 1/4 redes | Accionar `BusSwitch` (tras enable) | Side Socket (impulsor eléctrico / puerta rápida) | Snapshot bus; `test_dome_timeline:124-160` |
| **Beat 4 — Plasma** `Plasma/PlasmaValveA/B/C`, `PlasmaRoute` | `DomeMachineLevel.tscn:229-246`; wiring `:202-206, 272-279` | **OBLIGATORIO (test):** patrón `[1,0,1]` (`:245`) cierra la válvula del medio (`test_dome_timeline.gd:111-113`); 3/4 redes | Resolver la ruta de válvulas | Side Socket (lore + ventaja térmica) | Patrón requerido en `PlasmaRoute.required_pattern` |
| **Beat 5 — Aire** `Air/PressurePump`, `AirPurgeDial`, `AirPurgeTuner` | `DomeMachineLevel.tscn:283-358`; wiring `:208-211, 290-292` | **OBLIGATORIO (test):** purgar en zona verde (`test_dome_timeline.gd:116-120`); 4/4 redes | Sostener bomba + purgar en zona | Side Socket (lore) | `PressureSection` inyecta por tick (`DomeNetworkWiring.gd:87-89`) |
| **Apertura del blast door** `DomeSystemDirector._on_all_healthy` → `blast_door_open` → `BlastDoorController.on_blast_door_open` | `DomeSystemDirector.gd:363-370`; `BlastDoorController.gd:123-124, 138-145`; test `test_dome_timeline.gd:154-160` | **OBLIGATORIO (código/test):** es la **única** forma de bajar (compuerta de piso). Solo abre con 4/4 HEALTHY | 4/4 redes HEALTHY | **Núcleo del rediseño:** desacoplar la apertura de las 4 redes (p. ej. una palanca de emergencia / ruta de parkour por el pozo) | Es el gate más importante; cambia toda la ruta crítica del domo |
| **Pozo + rampa de servicio** `BlastDoorController/ServiceRamp` (`Flight1`/`Landing`/`Flight2`) | `core_v2/props/doors/BlastDoorController.tscn:123-149` | **Condición de descenso:** la rampa estática es la vía peatonal **sin esperar**; complementa a la plataforma | Blast door abierta | Ya es el **atajo opcional** (vía rápida peatonal) frente a la plataforma cinemática | Geometría de la rampa ligada al pozo |
| **Beat 6 — Plataforma de descenso** `HangarPlatform` | `core_v2/props/hangar/HangarDescent.tscn:25`; script `core_v2/props/hangar/HangarPlatform.gd` | **OPCIONAL (código):** vía cinemática; existe la rampa peatonal alternativa (FD-289 §7.9). Test de determinismo `test_dome_timeline.gd:289-319` | Subirse y descender | Ya es Side Socket (ruta «cine» con tremor/SFX) | Snapshot de posición/velocidad |
| **Beat 6 — Cinemática del descenso** `Cinematic/DescentGate` + `DescentRig` | `core_v2/props/hangar/HangarDescent.tscn:37-49` | **NO BLOQUEA el movimiento, pero enfoca la cámara** en el punto de transición (permitido por FD-321: cinemática **solo** en transición, no por área; `test_machine_bay_no_area_cinematics.gd`) | Se libera al cruzar el trigger (`HangarTransition._release_transition_camera`, `HangarTransition.gd:139-142`) | Mantener solo si no corta la corrida | `focus_camera` + latch (ver §1) |
| **Beat 6 → hangar** `HangarTransition` (Area) | `HangarTransition.gd:79-167`; `HangarDescent.tscn:31` | **OBLIGATORIO (código):** único camino a la escena del hangar; `change_scene` a `Dome_Intro_Hangar.tscn`, spawn `from_dome_intro_platform` (`:95-111, 144-166`) | Cruzar el fondo del pozo | Punto de transición (base del flow) | `test_hangar_transition.gd`; `preserve_player_state=false` |
| **Beat 7 — Hangar: puzzles físicos** `Puzzles/*` (Box_Vent, ConveyorMain, Carrousel, PressurePlate_Vent, DeliveryPad, Box_Bridge, Box_Heavy) | `core_v2/levels/interiors/Dome_Intro_Hangar.tscn:241-289` | **NO BLOQUEA hoy (implementación incompleta):** el FD-289 §5 Beat 7 dice «puzzles despejan la ruta a la esclusa», pero **la escena no tiene ningún gate/blocker/trigger ligado a los puzzles** (grep: sin `Gate`/`Blocker`/`Link` en el `.tscn`); el test solo comprueba que los props existen (`test_dome_intro_hangar.gd:84-89`) | — (hoy nada) | **Side Socket perfecto:** puzzles opcionales que dan **carga de tool / atajo** sin bloquear la salida | Si se decide cablearlos como gate, contradice la regla de oro |
| **Beat 7 — Salida del hangar** `Exit/Airlock_Exit` → `AirlockZoneV2` | `Dome_Intro_Hangar.tscn:322-328` | **OBLIGATORIO (código/test):** única frontera presurizada→vacío; `test_dome_intro_hangar.gd:97-108` (exactamente 1 airlock, target `ScaffoldOrbit`, spawn `from_dome_intro_hangar`) | Presurizar/abrir la esclusa | Punto de salida final | `AirlockControllerV2`; cambio de escena al exterior |
| **Beat 8 — Fin del slice (exterior)** `ScaffoldOrbit` | `DomeEnvConfig_intro.tres` (`exterior_airlock_scene`); `test_dome_timeline.gd:324-338` | OBLIGATORIO como destino final | Cruzar la esclusa del hangar | — | — |
| **(Acceso) Esclusa radial RingHub→bahía** `BayConnector` + `BayAirlockTrigger` | `core_v2/props/tube/BayAirlockTrigger.gd`; `docs/agents/sessions/2026-11-13_conexion_domo_bahia.md`; alternativa por botón `Hub/PedestalMachineBay` (`RingHub_Level.tscn:676`) → `RingHubLightState.enter_machine_bay()` (`RingHubLightState.gd:192`) | **NO bloquea el domo**; es la entrada a la bahía (fuera de la progresión del domo) | Cruzar la esclusa / accionar el pedestal | El conector físico puede ser el «FlowMarker» de entrada a la bahía | No toca SceneManager/AirlockManager (contrato del conector) |

---

## 4. Tests existentes que asumen el orden obligatorio (y qué habría que adaptar)

| Test | Qué asume | Impacto si el bloqueo pasa a Side Socket |
|---|---|---|
| `test_dome_timeline.gd:124-160` | ciclo **1→5 en orden canónico** con props reales, y `blast_door_open` solo a 4/4 | **Adaptar:** si se desacopla el blast door de las 4 redes, este test deja de probar el gate; hay que reescribirlo para el nuevo camino |
| `test_dome_timeline.gd:165-193` | gating fino del bus (`require_coolant_for_bus`) | Se conserva si coolant sigue siendo prerequisito; si no, marcar como caso opcional |
| `test_dome_timeline.gd:198-228` | buffer out-of-order: el director reordena a la secuencia canónica | **Ya contempla** sanar fuera de orden; es la base para hacer redes opcionales sin saltear beats |
| `test_dome_timeline.gd:233-284` | snapshot/restore a mitad del ciclo reproduce el final | Se conserva (determinismo) |
| `test_dome_timeline.gd:289-338` | beat 6 (plataforma) y beats 7/8 (hangar + esclusa) | Se conserva; si la plataforma deja de existir, recortar |
| `test_dome_systems.gd:111-136` | config intro: 4 redes + timeline de 5 acciones | Adaptar si el timeline cambia (nuevas acciones/beats) |
| `test_dome_systems_wiring.gd` (T6/T7) | cableado red→HEALTHY y acciones del timeline | Revisar si se agregan redes/acciones opcionales |
| `test_machine_bay_route.gd:169-276` | entrada → Estación 1 con CheckZones/KillFloor activos y **sin latch** (`:176`) | Base del «recorrido real»; extenderlo a la travesía completa es el test que hoy **falta** para poder afirmar el fin de la obligatoriedad de las estaciones |
| `test_machine_bay.gd:162-256` | balística por estación (E1–E4), **teletransporta** y **desactiva** zonas (`:35-40`) | Se conserva mientras las estaciones existan como boosters; los apogeos (`>6.5`, `max_z>34`, masas, centrífuga) son contratos de física |
| `test_machine_bay.gd:280-364` | Orden 0001 (válvula + botón) e idempotencia | Adaptar si cerrar la Orden deja de ser requisito |
| `test_machine_bay_maze_routing.gd:60-165` | topología de compuertas, apertura por progreso, pureza, colisión del barrier | Adaptar los **requisitos** (`SeesawLever`/`PendulumLever`) si las máquinas pasan a Side Sockets |
| `test_machine_bay_no_area_cinematics.gd` | MachineBay sin `CameraZone`/`CinematicRig` por área (FD-321) | **Guardia a respetar**: los Side Sockets no deben reintroducir cinemáticas de área |
| `test_hangar_descent.gd:51-101` | prefab del descenso (plataforma + trigger + cámara) e instancia en `Dome_Intro` | Se conserva; si el descenso se vuelve peatonal, revisar la parte de plataforma |
| `test_hangar_transition.gd:60-165` | destino por export/config, guard de disparo único, gracia post-carga | Se conserva |
| `test_dome_intro_hangar.gd:52-108` | hangar carga, spawn, 2 niveles, props de puzzle, esclusa a `ScaffoldOrbit` | Se conserva; es la evidencia de que **los puzzles del hangar no son gate hoy** |

> **OYS deterministas / replays:** los `KillZoneV2`/`CheckZoneV2`, las compuertas `MazeRoutingGate`,
> `BlastDoorController`, `HangarPlatform` y `DomeSystemDirector` están en `replay_sync` con
> `get_snapshot/restore_snapshot`. Convertir estaciones en Side Sockets **no debe** cambiar el
> orden de consumo de input ni introducir `randf`/`Engine.get_frames_drawn` (AGENTS.md §5.3). El
> precedente sensible ya documentado es `test_machine_bay.gd` (balística) y `test_determinism_v2`.

---

## 5. Puntos de bifurcación natural (para que ANNA / `agents/` marque el flow)

ANNA tiene gyms y política entrenados justo para estos mapas
(`agents/release/anna_mapgyms_2026-11-13/REPORT.md`: `TestScene_RL_MachineBayCorridor` y
`TestScene_RL_RingHubRing`, éxito 100% a 60 Hz). El actor holográfico ya expone la API de guiado
`guide_to(target_pos, speed)` (`core_v2/actors/ProgrammerHoloNPC.gd:234`), hoy usada por el layout
(`machine_bay.json:199, 220`) y por el acceso radial (`RingHubLightState.gd:253-254`).

Bifurcaciones donde conviene sembrar marcadores de flow / Side Sockets:

1. **Entrada del corredor (z≈4.5).** Primer fork real: corredor vs `maze_entry` (siempre abierta).
   Marcador «ruta principal» + aviso de laberinto lateral.
2. **Salida de Estación 1 (`maze_exit`).** Al completar el balancín se abre el atajo lateral →
   punto natural para que ANNA señale «atajo desbloqueado».
3. **Salida de Estación 2 (`field_link`).** Se abre el campo WFC → marcador de lore/carga de tool.
4. **RingHub piso 0 (esclusa radial, `BayConnector`).** Bifurcación de acceso al nivel: botón
   (`PedestalMachineBay`) vs boca física. Ideal para el flow de entrada a la bahía.
5. **Nivel de máquinas del domo.** Tras cada red HEALTHY el semáforo del blast door cambia
   (`BlastDoorController._apply_semaphore`, `:176-199`): cuatro sub-puntos de guía (un manómetro
   por red) donde ANNA puede dirigir al siguiente sistema.
6. **Pozo del blast door.** Bifurcación de descenso: **plataforma** (cinemática) vs **rampa de
   servicio** (peatonal, sin espera). Punto de decisión claro para el flow.
7. **Hangar.** Catwalks/rampa vs puzzles físicos: bifurcación natural para Side Sockets de
   recompensa (tool/lore) sin bloquear la esclusa.

---

## 6. Resumen ejecutivo — bloqueos obligatorios hoy

**MachineBay (corredor):** Estaciones **1 (balancín), 2 (péndulo), 3 (catapulta), 4 (brazo
centrífugo)** son OBLIGATORIAS **por geometría** (huecos + `KillFloor` y=−18): sin ellas no se
cruza el nivel. La **Válvula Maestra / Orden 0001** es obligatoria para *cerrar* la demo pero no
para moverse. `ReturnHubButton` es el fin de demo. **No existe test de travesía completa sin
máquinas** (el único recorrido con input cubre entrada→E1). Los triggers de voz con `focus_camera`
**congelan el input** temporalmente (latch).

**MachineBay (laberinto/ruteo):** **ya es opcional**; el corredor es la ruta crítica intacta.
Único matiz: hoy los atajos se abren con las palancas del corredor.

**Domo de Introducción:** el **blast door** es el gate central y **solo abre con 4/4 redes
HEALTHY**; las 4 redes son obligatorias y el **bus eléctrico está gateado por el coolant**
(`require_coolant_for_bus`). El descenso tiene vía peatonal (rampa) además de la plataforma
cinemática. El hangar **no** gatea los puzzles (la salida ya es libre hoy). El acceso radial
RingHub→bahía no condiciona la progresión del domo.

**Bloqueos a reescribir para Transit-Run:** (1) apertura del blast door atada a 4/4 redes;
(2) estaciones 1–4 como único medio de cruzar el corredor; (3) gating del bus por coolant;
(4) `focus_camera` que corta la corrida en los triggers de voz.

---

## 7. Verificación / alcance

- Ningún test nuevo. No se corrió la suite completa (AGENTS.md §6.1).
- Toda afirmación de «obligatorio» se ancló a código o test con `archivo:línea`; donde solo la
  geometría lo sostiene (§1, E1–E4) se explicitó «OBLIGATORIO (geometría)» y la base exacta.
- Este mapa es el insumo para la aprobación de Sebastián antes de la fase 2 (conversión a Side
  Sockets).
