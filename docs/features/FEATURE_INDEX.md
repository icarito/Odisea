# FEATURE_INDEX.md — Odisea Acto I

## Product Direction 2026-05-23

El foco inmediato no es cerrar todas las features abiertas. El foco es producir
una vertical slice jugable que permita:

1. construir niveles de plataformas rapidamente;
2. moverse sin cortes perceptibles entre interiores y zonas de nave/espiral;
3. validar el frame centrifugo sin meter fisica de gameplay dentro de
   `WorldRotator`;
4. mantener los fondos de nave baratos en GLES2.

### Slice Recomendada

**Objetivo:** una ruta corta y rejugable: interior -> airlock/tubo -> plate
centrifuga con plataformas -> objetivo -> transicion a otra sala.

| Orden | FD | Trabajo | Resultado esperado |
|-------|----|---------|--------------------|
| 1 | FD-021 | Scene Transition System | `SceneManager` + airlocks con pre-carga del destino cercano y preservacion de posicion. |
| 2 | FD-040 | PlateContentStream Authoring | Sub-escenas de gameplay por plate, autorables desde Inspector, fuera de `WorldRotator`. |
| 3 | FD-026 | Goal Beacon | Primer loop de final de nivel y evento de completado. |
| 4 | FD-025 | Tube / Airlock Connector Kit | Conectores fisicos/visuales para unir interiores, plates y rutas de prueba. |
| 5 | FD-020 | WallManager Area | Camara legible en interiores estrechos sin romper exteriores. |
| 6 | FD-032 | Seamless Startup/Area Streaming | Solo lo necesario para esconder carga entre escenas cercanas; no bloquear el slice por streaming global. |
| 7 | FD-041 | Faux Skydome / Parallax Shell | Fondo barato para casco, exterior, estrellas y espiral sin scaffold infinito completo. |

### Arquitectura De Nivel Recomendada

Usar tres capas separadas:

| Capa | Duenio | Que contiene | Regla |
|------|-------|--------------|-------|
| Gameplay fisico | Nivel raiz / `PlateContentRoot` | jugador, triggers, pisos, props interactivos, plataformas, puzzles | Nunca depender de fisica bajo `WorldRotator` para contenido nuevo. |
| Frame visual centrifugo | `WorldRotator` | espiral, casco, fondos, LOD visual, scaffold barato, sky/parallax | Visual-only o fisica legacy documentada. |
| Transicion/streaming | `SceneManager` + portales | interiores, airlocks, chunks cercanos, fade/camera masks | Preload de vecinos antes de cruzar para evitar delay visible. |

### Decisiones De Producto Guardadas

- **Unidad jugable:** usar `SceneManager` con varias escenas pequenas o terrazas
  conectadas por una escena/layout grande optimizada. No construir todo Acto I
  como una sola escena monolitica.
- **Transicion principal:** airlocks. La fantasia encaja con Odisea y debe
  reemplazar el boceto actual que no funciona bien.
- **Delay aceptable:** aspirar a cero pausa visible, pero aceptar mascara corta
  si el airlock/camara lo justifica.
- **Camara:** mantener 3ra persona como regla. En espacios constrenidos, probar
  una 3ra persona mas cercana y levemente dislocada al estilo Sifu.
- **Rampa de libertad:** empezar con control familiar, introducir la espiral y
  gravedad centrifuga relativamente temprano como momento de sorpresa/awe.
- **Skydome/parallax:** debe vender casco, estrellas exteriores y la espiral en
  si; no solo abstraccion interna.
- **0G:** prototipar. Si resulta divertido, incluirlo en Acto I; si no, queda
  como seccion posterior.

## Active Backlog

### P0 — Desbloquea construir niveles

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-021 | Scene Transition System | Implemented / Vertical | Medium | P0 | `TransitionPortal` usa `SceneManager`, airlock/fade/instant, spawn anchor, snapshot e input lock. |
| FD-040 | PlateContentStream Stability and Inspector Authoring | Verified / In Progress | Small | P0 | Terminar authoring para que una plate pueda contener una sub-escena jugable sin tocar `WorldRotator`. |
| FD-026 | Goal Beacon | Planned | Small | P0 | Sin objetivo no hay loop de nivel testeable. |
| FD-025 | Tube / Airlock Connector Kit | Planned | Small | P0 | Kit de airlock/conector para transiciones y rutas de plataformas. |
| FD-020 | WallManager Area | In Progress | Medium | P0 | Necesario para interiores jugables con camara 3ra persona. |

### P1 — Mejora inmersion y continuidad

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-032 | Seamless Startup Streaming | In Progress | Large | P1 | Usar incrementalmente: primero vecinos de transicion, luego chunks grandes. |
| FD-036 | Gravity Manager - World-Rotation Approach | Implemented / In Progress | Medium | P1 | Mantener contrato; no reabrir `up` dinamico. |
| FD-039 | Gravity Physics Strategy for Godot 3 | Implemented / Revised | Medium | P1 | Fuente de verdad tecnica para fisica/espiral. |
| FD-033 | Advanced Traversal Systems | In Progress | Large | P1 | Solo ladder/ledge core si el primer nivel lo necesita. Ropes/wall climb quedan fuera del slice. |
| FD-034 | Player Interaction Hints | Planned | Medium | P1 | Ayuda a teachability de portales, objetivos y props; no debe bloquear el primer layout. |

### P2 — Ambiente, escala y prototipos

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-041 | Faux Skydome / Centrifugal Parallax Shell | Design | Medium | P2 | Experimento visual barato para vender casco, exterior, espiral y rotacion antes del scaffold completo. |
| FD-037 | Infinite Scaffold Field | Design | Large | P2 | Mantener como visual infrastructure. No integrarlo a `BaseTerrace` hasta fijar presupuesto. |
| FD-038 | ZeroGravityController & Controller Swapping | Design / Prototype | Medium | P2 | Spike jugable: si el prototipo 0G es divertido, sube al slice de Acto I. |
| FD-035 | ConveyorCarrousel & Conveyor Enhancements | Design | Medium | P2 | Buen puzzle prop, pero no es prerequisito para la ruta base. |
| FD-022 | BGM Audio Manager | Planned | Medium | P2 | Importante para polish de transiciones, no para arquitectura. |
| FD-027 | Spawn Cinematic / ScreenBorders | In Progress | Medium | P2 | Usar para ocultar entrada/retry si ya existe, no expandir ahora. |

### P3 — Contenido posterior

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-019 | Multiplayer Split-screen | In Progress | Large | P3 | Congelar salvo bugs. Multiplica QA de camara/transiciones. |
| FD-028 | Plasma Leak Obstacle | Planned | Small | P3 | Contenido de hazard luego del slice. |
| FD-029 | DDC Drone | Planned | Medium | P3 | NPC/sistema posterior. |
| FD-030 | Cargol NPC | Planned | Medium | P3 | NPC posterior. |
| FD-031 | Narrative Dialogs (IA) | Planned | Large | P3 | Postergar hasta que el loop jugable pida dialogos. |

## Recommended Next Work

### 1. Cerrar contrato de transicion

Definir `FD-021` con una API concreta, apoyandose en lo que ya existe:

- `TransitionPortal` con `target_scene`, `target_spawn_id`,
  `activation_mode`, `transition_style` y `mask_style`.
- `SceneManager` debe poder precargar/cargar el destino mientras el jugador aun
  esta en el airlock.
- La transicion ideal para interiores <-> espiral debe sentirse como airlock.
  Fade/mascara corta queda como fallback pragmatica.
- El test minimo debe cruzar ida/vuelta preservando transform y modo de gravedad.
- Reusar `core_v2/autoloads/SceneManager.gd`,
  `core_v2/autoloads/TransitionLayer.gd`,
  `core_v2/props/AirlockChamber.tscn` y
  `core_v2/components/AirlockControllerV2.gd`.

### 2. Crear una escena de layout Acto I

Proponer una escena dedicada de authoring:

```text
Act1PlatformSlice.tscn
+-- PlayerStart
+-- Interior_A
+-- AirlockConnector_A
+-- WorldRotator
+   +-- TerraceSpiralVisual
+   +-- FauxSkydomeParallaxShell
+-- PlateContentRoot
+   +-- PlateSlotConfig_0_12 -> PlatformRoom_A.tscn
+   +-- PlateSlotConfig_0_13 -> GoalPlate_A.tscn
+-- TransitionPortal_ToInteriorB
```

Esto permite construir y testear niveles sin esperar a que `BaseTerrace` deje de
ser hibrida/legacy.

### 3. Probar skydome/parallax como sustituto temporal del scaffold lejano

El skydome falso deberia ser una capa visual bajo `WorldRotator`, no gameplay:

- shell cilindrico o esferico invertido con casco, estrellas exteriores y
  lectura clara de la espiral;
- 2-3 capas con scrolling/parallax sutil segun camara o frame canonico;
- rotacion visual sincronizada con el `WorldRotator`;
- sin colision, sin miles de nodos, sin luces dinamicas costosas;
- opcion de desactivar en perfil bajo.

El criterio de exito es simple: si vende escala y rotacion por menos costo que
el scaffold lejano, se queda como LOD lejano de FD-037. Si causa mareo o popping,
se descarta sin tocar gameplay.

## Project Context For Next Session

### Existing Pieces To Reuse

| Area | Existing file | Note |
|------|---------------|------|
| Scene loading | `core_v2/autoloads/SceneManager.gd` | Ya usa `ResourceLoader.load_interactive()`, captura/restaura player snapshot y soporta `target_spawn_id`. |
| Visual mask | `core_v2/autoloads/TransitionLayer.gd` | Fade/loading simple; suficiente como fallback de airlock. |
| Airlock prop | `core_v2/props/AirlockChamber.tscn` | Boceto existente; necesita integracion real con transicion de escena. |
| Airlock logic | `core_v2/components/AirlockControllerV2.gd` | Deterministico y `replay_sync`; puede servir como base, pero hoy solo maneja puertas/presurizacion local. |
| Plate authoring | `core_v2/systems/PlateContentStream.gd`, `core_v2/systems/PlateSlotConfig.gd` | Ruta oficial para contenido con fisica en plates. |
| Camera zones | `core_v2/components/CameraZone.gd` | Base para camara fija/cercana en interiores constrenidos. |
| 0G prototype | `core_v2/player/ZeroGravityController.gd`, `core_v2/props/ZeroGravityZone.tscn` | Existe ruta separada; falta decidir si es divertido para Acto I. |

### Next Session Start

1. Abrir `FD-021` y convertirlo en implementacion de `TransitionPortal` sobre
   `SceneManager`, no en un sistema paralelo.
2. Hacer un test scene minimo: `Interior_A -> AirlockChamber -> Terrace_A`.
3. Validar ida/vuelta con `target_spawn_id`, snapshot del player y modo de
   gravedad preservado.
4. Recién despues conectar `PlateContentStream` con dos sub-escenas de plate.
5. Si la ruta se siente estable, prototipar `FD-041` como visual bajo
   `WorldRotator`.

## Completed / Archived

| FD | Title | Completed | Notes |
|----|-------|-----------|-------|
| FD-001 | OdysseyScript DSL | 2026-01-07 | `archive/FD-001_odyssey_script.md` |
| FD-002 | OdysseyScript Replay | 2026-01-07 | `archive/FD-002_odyssey_script_replay.md` |
| FD-003 | Test Runner (GDUnit3) | 2026-01-07 | `archive/FD-003_test_runner.md` |
| FD-004 | PushableBoxV2 | 2026-01-10 | `archive/FD-004_pushable_box.md` |
| FD-005 | Movement Gamefeel | 2026-01-12 | `archive/FD-005_movement_gamefeel.md` |
| FD-006 | Sidescroller Zone | 2026-01-12 | `archive/FD-006_sidescroller_zone.md` |
| FD-007 | Test Battery | 2026-01-13 | `archive/FD-007_test_battery.md` |
| FD-008 | ANNA Agent (ML/CV) | 2026-02-15 | `archive/FD-008_anna_agent.md` |
| FD-009 | Interaction System | 2026-02-17 | Implemented; no standalone archive doc currently. |
| FD-010 | OLCS (Logic Circuit) | 2026-02-17 | `archive/FD-010_olcs.md` |
| FD-011 | Props Pipeline | 2026-02-17 | `archive/FD-011_props_pipeline.md` |
| FD-012 | Elevator | 2026-02-17 | `archive/FD-012_elevator.md` |
| FD-013 | HoloTerminal Cinematic | 2026-02-20 | `archive/FD-013_holo_terminal.md` |
| FD-014 | VCamera Integration | 2026-02-21 | `archive/FD-014_vcamera_cinematic.md` |
| FD-015 | Subtitles PRINT/ASSERT | 2026-02-19 | `archive/FD-015_subtitles.md` |
| FD-016 | Retro UI Workbench | 2026-02-18 | `archive/FD-016_retro_ui_workbench.md` |
| FD-017 | Emitter/Destroyer Areas | 2026-02-17 | `archive/FD-017_emitter_destroyer.md` |
| FD-018 | Automatic Prop Zoo | 2026-02-16 | `archive/FD-018_prop_zoo.md` |
| FD-023 | WindZone | 2026-03-02 | `archive/FD-023_windzone.md` |
| FD-024 | Guardrail Platform | 2026-03-02 | `archive/FD-024_guardrail.md` |

## Status Legend

- **Planned**: Identified, not yet designed
- **Design**: Actively designing the solution
- **Open**: Designed, ready for implementation
- **In Progress**: Currently being implemented
- **Pending Verification**: Code complete, awaiting runtime verification
- **Complete**: Verified working, ready to archive
- **Deferred**: Postponed indefinitely
- **Closed**: Won't do

## Gravity / Physics Contract Docs

Agents touching gravity, centrifugal terraces, zero-G, streamed plate content, or
scaffold performance must read:

- `docs/engineering/Gravity_Physics_Contracts.md`
- `docs/features/FD-036_gravity_manager.md`
- `docs/features/FD-039_gravity_physics_strategy.md`
- `docs/features/FD-040_plate_content_stream_stability.md`
