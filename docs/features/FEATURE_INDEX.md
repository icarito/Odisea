# FEATURE_INDEX.md — Odisea Acto I

## Product Direction 2026-05-29

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
| 1 | FD-021 | Scene Transition System | SceneManager + airlocks con pre-carga, snapshot, camera yank fix. |
| 2 | FD-042 | Over-the-Shoulder Camera | Camara al hombro en espacios estrechos. |
| 3 | FD-040 | PlateContentStream Authoring | Sub-escenas de gameplay por plate. |
| 4 | FD-026 | Goal Beacon | Primer loop de final de nivel. |
| 5 | FD-025 | Tube / Airlock Connector Kit | Conectores para interiores y plates. |
| 6 | FD-020 | WallManager Area | Camara legible en interiores estrechos. |
| 7 | FD-032 | Seamless Startup/Area Streaming | Esconder carga entre escenas. |
| 8 | FD-041 | Faux Skydome / Parallax Shell | Fondo barato para casco y espiral. |

### Arquitectura De Nivel Recomendada

Usar tres capas separadas:

| Capa | Duenio | Que contiene | Regla |
|------|-------|--------------|-------|
| Gameplay fisico | Nivel raiz / PlateContentRoot | jugador, triggers, pisos, props interactivos | Nunca depender de fisica bajo WorldRotator. |
| Frame visual centrifugo | WorldRotator | espiral, casco, fondos, LOD | Visual-only. |
| Transicion/streaming | SceneManager + portales | interiores, airlocks, chunks | Preload de vecinos antes de cruzar. |

### Decisiones De Producto Guardadas

- **Unidad jugable:** SceneManager con varias escenas pequenas conectadas.
- **Transicion principal:** airlocks con precarga async.
- **Delay aceptable:** aspirar a cero, aceptar mascara corta.
- **Camara:** 3ra persona, OTS en espacios estrechos.
- **Rampa de libertad:** control familiar -> espiral centrifuga como sorpresa.
- **Skydome/parallax:** casco + estrellas + espiral.
- **0G:** prototipar; si es divertido, incluir en Acto I.

## Active Backlog

### P0 — Desbloquea construir niveles

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-021 | Scene Transition System | Implemented | Medium | P0 | AirlockZoneV2 con carga async, snapshot, camera yank fix. |

| FD-042 | Over-the-Shoulder Camera | Implemented | Small | P0 | Desplaza camara al hombro, compensacion de salto. |
| FD-040 | PlateContentStream Authoring | In Progress | Small | P0 | Sub-escenas jugables por plate. |
| FD-026 | Goal Beacon | Planned | Small | P0 | Loop de nivel testeable. |
| FD-025 | Tube / Airlock Connector Kit | Planned | Small | P0 | Kit de conectores. |
| FD-020 | WallManager Area | In Progress | Medium | P0 | Camara en interiores. |

### P1 — Mejora inmersion y continuidad

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-032 | Seamless Startup Streaming | In Progress | Large | P1 | Vecinos de transicion, luego chunks. |

| FD-036 | Gravity Manager | Implemented | Medium | P1 | World-rotation approach. |
| FD-039 | Gravity Physics Strategy | Implemented | Medium | P1 | Fuente de verdad para fisica/espiral. |
| FD-033 | Advanced Traversal | In Progress | Large | P1 | Ladder/ledge core si el nivel lo necesita. |
| FD-034 | Player Interaction Hints | Planned | Medium | P1 | Teachability de portales, objetivos, props. |

### P2 — Ambiente, escala y prototipos

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-250 | Dome_Intro bake reproducible + iluminación híbrida | In Progress | Large | P2 | Recuperar fuentes editables, rebake estable y reducir luces runtime. |
| FD-261 | Dome_Intro bake tuberías + letreros | Implemented | Small | P2 | Fusiona red de coolant y letreros estáticos en 2 draw calls; fix frost airlock más cercano. |
| FD-041 | Faux Skydome / Parallax Shell | Design | Medium | P2 | Fondo barato para casco y espiral. |
| FD-037 | Infinite Scaffold Field | Design | Large | P2 | Visual infrastructure. |
| FD-038 | ZeroGravityController | In Progress | Medium | P2 | Prototipo jugable. |
| FD-035 | ConveyorCarrousel | Design | Medium | P2 | Puzzle prop. |
| FD-022 | BGM Audio Manager | Planned | Medium | P2 | Polish de transiciones. |
| FD-027 | Spawn Cinematic / ScreenBorders | In Progress | Medium | P2 | Ocultar entrada/retry. |


### P3 — Contenido posterior

| FD | Title | Status | Effort | Priority | PM Note |
|----|-------|--------|--------|----------|---------|
| FD-019 | Multiplayer Split-screen | In Progress | Large | P3 | Congelado. |
| FD-028 | Plasma Leak Obstacle | Superseded | Small | P3 | Reemplazado por FD-257 (sistema plasma). |
| FD-029 | DDC Drone | Planned | Medium | P3 | NPC posterior. |
| FD-030 | Cargol NPC | Planned | Medium | P3 | NPC posterior. |
| FD-031 | Narrative Dialogs (IA) | Planned | Large | P3 | Postergar hasta que el loop jugable pida dialogos. |

## Active Backlog (Post-FD-239)

### P0 — Contenido jugable del Acto I

| FD | Title | Status | Effort | Priority |
|----|-------|--------|--------|----------|
| FD-240 | Blockout Módulo Criogenia | Planned | Medium | P0 |
| FD-241 | Cargol V2 — Compañero Funcional | Design | Medium | P0 |
| FD-242 | DDC Drone + Sigilo Básico | Design | Medium | P0 |
| FD-243 | Diálogo Odisea y Lore Pickup | Planned | Large | P1 |
| FD-244 | Multi-Tool — Láser + Gloo Gun | Design | Medium | P0 |
| FD-255 | Los 4 Sistemas de la Nave (maestro) | Implemented | Medium | P0 |
| FD-256 | Sistema Criocoolant (CryoVent) | Implemented | Small | P0 |
| FD-257 | Sistema Plasma | Implemented | Small | P0 |
| FD-258 | Sistema Atmósfera (Presión) | Implemented | Small | P0 |
| FD-259 | Sistema Energía Auxiliar | Implemented | Small | P0 |
| FD-260 | Signage — configuración y legibilidad | In Progress | Small | P2 |
| FD-261 | Editor de circuitos usable (Dome_Intro) | Design | Small | P2 |
| FD-262 | Generador procedural de rutas de tuberías | Design | Medium | P1 |
| FD-263 | Touch universal (tap interact + detección runtime) | Design | Medium | P0 |
| FD-264 | Lógica de circuitos de coolant (grafo de flujo OCLS) | Design | Medium | P0 |
| FD-269 | Room3D — estado ambiental por habitación (temp/presión/contaminación) | Design | Medium | P0 |

## Completed / Archived

| FD | Title | Completed | Notes |
|----|-------|-----------|-------|
| FD-001 a FD-018 | Sistema inicial | 2026-01/02 | Archivados en docs/features/archive/ |
| FD-021 | Scene Transition System | 2026-05-29 | AirlockZoneV2, camera yank fix. |
| FD-042 | Over-the-Shoulder Camera | 2026-05-29 | OTS en espacios estrechos. |
| FD-231 | Main Menu & Pause | 2026-06-22 | Screen, keyboard/gamepad, pause. |
| FD-232 | FireEmitter Fix | 2026-06-22 | Reparar FireEmitter + Beacon. |
| FD-233 | ZeroG Inertia Layer | 2026-06-22 | Newtoniana en 0G. |
| FD-234 | Version Display | 2026-06-22 | Versión en boot y menú. |
| FD-235 | Performance Pass | 2026-06-22 | LOD + instrumentación. |
| FD-238 | FD System Improvements | 2026-06-22 | Skills docs, CHANGELOG, fd-close. |
| FD-023 | WindZone | 2026-03-02 | archive/ |
| FD-024 | Guardrail Platform | 2026-03-02 | archive/ |

## Status Legend

- **Planned**: Identified, not yet designed
- **Design**: Actively designing
- **In Progress**: Currently being implemented
- **Implemented**: Code complete
- **Complete**: Verified working
- **Deferred**: Postponed

## Existing Pieces To Reuse

| Area | File | Note |
|------|------|------|
| Scene loading | core_v2/autoloads/SceneManager.gd | load_interactive, snapshot, spawn_id |
| Visual mask | core_v2/autoloads/TransitionLayer.gd | Fade/loading |
| Airlock | core_v2/components/AirlockZoneV2.gd | Transicion con precarga |
| Airlock prop | core_v2/props/AirlockChamber.tscn | Tunel de 8m |
| Airlock logic | core_v2/components/AirlockControllerV2.gd | Puertas + presurizacion |
| Plate authoring | core_v2/systems/PlateContentStream.gd | Contenido por plate |
| Camera zones | core_v2/components/CameraZone.gd | Camara fija en interiores |
| Over-the-shoulder | core_v2/player/OverTheShoulder.gd | Camara al hombro |
| HoloTerminal V2.3 | core_v2/things/HoloTerminalV2.gd | Terminal interactiva (cinematic cam, focus mode, HUD bridge) |
| WallTerminal | core_v2/props/WallTerminal.tscn | Terminal de pared |
| TableTerminal | core_v2/props/TableTerminal.tscn | Terminal de mesa |
| HelmetHUD | core_v2/props/HelmetHUD.tscn | HUD acoplable a camara |
| Interaction base | core_v2/things/InteractableBaseV2.gd | Base replay-determinista |
| 0G prototype | core_v2/player/ZeroGravityController.gd | Gravedad cero |
| RadialScatter | core_v2/tools/RadialScatter.gd | Disposicion radial de escenas |

## Gravity / Physics Contract Docs

Agents touching gravity, centrifugal terraces, zero-G, streamed plate content, or
scaffold performance must read:

- docs/engineering/Gravity_Physics_Contracts.md
- docs/features/FD-036_gravity_manager.md
- docs/features/FD-039_gravity_physics_strategy.md
- docs/features/FD-040_plate_content_stream_stability.md
