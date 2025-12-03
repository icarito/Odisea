# TODO — MVP Acto I (Experiencia Continua en `criogenia.tscn`)

Objetivo: Completar un primer nivel continuo (sin cambios de escena) con plataformas móviles, barandas, tubos conectores, conveyor, objetivos claros, fuerzas de viento, cajas apilables y sistema de muerte/respawn.

## TODO Pendiente

| Prioridad | Tarea | Detalles/Notas |
|-----------|-------|----------------|
| Alta | Plataformas con barandas | Crear `scenes/common/GuardrailSegment.tscn` (StaticBody + Mesh modular) y rodear bordes de plataformas principales y móviles. Integrar en `Criogenia.tscn`. |
| Alta | Tubos conectores entre secciones | Crear `scenes/common/TubeConnector.tscn` (CSGCylinder/CSGTorus + StaticBody) y conectar plataformas/alas. Añadir entradas legibles. |
| Alta | Conveyor en plataforma principal | Calibrar empuje en `criogenia.tscn` (ya implementado, pendiente ajuste fino). |
| Alta | Objetivo de alto contraste | Crear `scenes/common/GoalBeacon.tscn` (Mesh + Area) para marcar objetivo. |
| Alta | Bloques apilables | Crear `scenes/common/PushableBox.tscn` (RigidBody) con fricción/masa para apilar 2-3 cajas. |
| Alta | Spawn cinematográfico y cutscenes | Crear `scenes/common/ScreenBorders.tscn` y extender `scripts/SceneSpawn.gd` con exports para transiciones. |
| Media | Integrar “Cargol” | Crear `scenes/common/Cargol.tscn` y ubicarlo en `criogenia.tscn`. |
| Media | SceneManager y Loading Screens | Añadir autoload SceneManager para pantallas de carga. |
| Baja | Integración de audio y Cargol | Adjuntar `scripts/LevelBGM.gd` al nivel. |
| Baja | Pruebas y balance | Probar apilado de cajas y respawn en checkpoints. |
| Baja | Entregables del MVP | Asegurar `Criogenia.tscn` con todas las piezas listadas. |

## Convenciones de capas de colisión (propuesta MVP)
- Player (KinematicBody): layer 1, mask: 2 (entorno), 3 (plataformas móviles), 4 (conveyor), 5 (wind), 6 (checkpoints), 7 (kill), 8 (cajas). No colisionar con layer 9 (cámara helpers).
- Entorno estático: layer 2, mask: 1 (player), 8 (cajas).
- Plataformas móviles: layer 3, mask: 1 (player), 8 (cajas), 2 (entorno) — evitar choques entre plataformas.
- Conveyor (Area): layer 4, mask: 1 (player), 8 (cajas).
- WindZone (Area): layer 5, mask: 1 (player), 8 (cajas).
- Checkpoint (Area): layer 6, mask: 1 (player).
- KillZone (Area): layer 7, mask: 1 (player), 8 (cajas).
- Cajas (RigidBody): layer 8, mask: 2 (entorno), 3 (plataformas), 8 (otras cajas).
- Cámara helpers: layer 9, mask: 2 (entorno).