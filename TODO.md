# TODO — MVP Acto I (Experiencia Continua en `criogenia.tscn`)

Objetivo: Completar un primer nivel continuo (sin cambios de escena) con plataformas móviles, barandas, tubos conectores, conveyor, objetivos claros, fuerzas de viento, cajas apilables y sistema de muerte/respawn.

## Prioridad Alta
- [ ] Plataformas con barandas
  - Crear `scenes/common/GuardrailSegment.tscn` (StaticBody + Mesh modular) y rodear bordes de plataformas principales y móviles, dejando huecos de salto.
  - Integrar en `scenes/levels/act1/criogenia.tscn` (plataforma principal + `PuzzleZone`).
- [ ] Tubos conectores entre alas
  - Crear `scenes/common/TubeConnector.tscn` (CSGCylinder/CSGTorus + StaticBody) y conectar plataformas/alas para navegación y backtracking.
  - Añadir entradas/salidas legibles (anillos luminosos).
- [ ] Conveyor en plataforma principal
  - Implementar `scripts/Conveyor.gd` + `scenes/common/Conveyor.tscn`.
  - Empuje tangencial configurable (`push_velocity`), ancho/longitud de banda y material con flechas.
  - Colocar en la primera plataforma principal.
- [ ] Objetivo de alto contraste
  - Crear `scenes/common/GoalBeacon.tscn` (Mesh + material emisivo/color contrastante + `Area`).
  - Al entrar en el `Area`, marcar objetivo: abrir compuerta, encender baliza o registrar progreso.
- [ ] Vientos/Fuerzas ascendentes
  - Implementar `scripts/WindZone.gd` + `scenes/common/WindZone.tscn` (`Area`) que aplica fuerza vertical configurable a cuerpos dentro.
  - Señalizar con partículas/flechas/sonido suave.
- [ ] Bloques apilables
  - `scenes/common/PushableBox.tscn` (`RigidBody`) con dimensiones estándar, fricción y masa para apilar/arrastrar.
  - Opcional: puntos de anclaje o “slots” guía para facilitar el apilado en MVP.
- [ ] Muerte por caída
  - `scripts/KillZone.gd` (Area grande bajo zona jugable) ⇒ muerte inmediata.
  - Opcional: `FallDamage.gd` para muerte si velocidad vertical/altura excede umbral.
- [ ] Respawn a estado viable
  - Extender `autoload/PlayerManager.gd` con checkpoints (`Checkpoint.tscn`) y snapshot de posición/rotación.
  - Al morir, respawn en el último checkpoint seguro.

## Integración con lo existente
- [ ] Ajustar `scripts/MovingPlatform.gd` si es necesario para transportar al jugador de forma estable (comprobar colisiones en bordes).
- [ ] Añadir `KillZone` y `WindZone` en `criogenia.tscn` (primera ala: plataformas + conveyor; segunda ala: salto con viento + cajas apilables).
- [ ] Materiales: usar `materials/interior/*` y `addons/kenney_prototype_textures` (marcas de dirección para conveyor/trayectorias).

## Implementación técnica (archivos nuevos)
- [ ] `scenes/common/GuardrailSegment.tscn` — segmento 2m con `StaticBody` + `CollisionShape` (altura ~1m).
- [ ] `scenes/common/TubeConnector.tscn` — CSG + `StaticBody` con colisión cilíndrica; entradas con borde luminoso.
- [ ] `scripts/Conveyor.gd` — aplica velocidad constante a `KinematicBody`/`RigidBody` dentro (por ejemplo, vector en tangente de banda). Exponer: `push_velocity`.
- [ ] `scenes/common/Conveyor.tscn` — `Area` + `CollisionShape` + Mesh plano con textura de flechas.
- [ ] `scripts/WindZone.gd` — aplica fuerza vertical; Exponer: `lift_force`, `max_speed`. Opción pulsante.
- [ ] `scenes/common/WindZone.tscn` — `Area` + `CollisionShape` + partículas direccionales.
- [ ] `scenes/common/PushableBox.tscn` — `RigidBody` + `CollisionShape` + Mesh cúbico; fricción alta.
- [ ] `scripts/KillZone.gd` — al entrar, emitir señal de muerte al `PlayerManager`.
- [ ] `scenes/common/KillZone.tscn` — `Area` grande bajo plataformas.
- [ ] `scenes/common/Checkpoint.tscn` — `Area` + marcador visual; notifica a `PlayerManager`.
- [ ] `scripts/GoalBeacon.gd` + `scenes/common/GoalBeacon.tscn` — activa objetivo y guarda progreso.

## Pruebas y balance
- [ ] Ajustar velocidades (`MovingPlatform.speed`, `wait_time`) y curvas (`data/Curves/*.tres`).
- [ ] Conveyor: calibrar `push_velocity` para que requiera correcciones pero no frustre.
- [ ] Viento: `lift_force` que permita ascenso controlado con salto planeado.
- [ ] Cajas: comprobar apilado estable (2–3 cajas), sin jitter excesivo.
- [ ] KillZone/Respawn: morir fuera de límites siempre respawnea en el último checkpoint.

## Entregables del MVP
- [ ] `criogenia.tscn` con: plataformas con barandas, conveyor activo, un tubo conector a ala secundaria, zona de viento para ascenso, cajas apilables para resolver un acceso, objetivo de alto contraste que concluye el recorrido.
- [ ] Actualizar `README.md` con controles y rutas: cómo alcanzar la baliza/objetivo y cómo usar viento/cajas/conveyor.
