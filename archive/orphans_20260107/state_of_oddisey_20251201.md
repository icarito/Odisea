# Estado Técnico — Odisea (2025-12-01)

Documento de referencia para agentes de research y arquitectura. Resume el estado actual del codebase (Godot 3.x / GLES2), sistemas implementados, limitaciones y una agenda de investigación centrada en “satisfying movement”.

## Resumen Ejecutivo
- Motor: Godot 3.x (sintaxis y estructura confirman 3.x; objetivo 3.6.x).
- Render: GLES2 (prioriza compatibilidad; restricciones en luces/shaders avanzados).
- Núcleo jugable: Tercera persona con `KinematicBody`, `AnimationTree` y plataformas móviles lineales A↔B; conveyor prototipo.
- Problema clave: Plataformas no transfieren velocidad al jugador y no siguen trayectorias curvas; falta de `snap` y de una interfaz de “velocidad externa” consistente.
- Foco research: Movimiento “satisfying” y robusto en KinematicBody sobre plataformas móviles (lineales y curvadas), con perfiles de aceleración, coyote time, buffering, cámara y control refinados.

---

## Stack y Configuración
- Godot: 3.x (3.6.x objetivo para editor y export).
- Renderer: GLES2 (config en `project.godot`: `quality/driver/driver_name="GLES2"`).
- Plataformas de destino: Linux/X11 y Android (carpeta `android/` con Gradle + `export_presets.cfg`).
- Display: `stretch.mode="viewport"`, `aspect="keep"`; fullscreen por defecto.
- Input: Acciones definidas para `forward/backward/left/right`, `aim`, `jump`, `attack`, `roll`, `sprint`, y mappings de prototipo (vehículos/UI).

## Arquitectura Actual (archivos clave)
- Jugador tercera persona:
  - `players/elias/PlayerController.gd`: control principal (KinematicBody + `move_and_slide`).
  - Animación: `AnimationTree` con `playback.travel/start` y parámetros booleanos.
  - Sensado: `RayCast` para suelo (sombra falsa) y `get_floor_normal()`.
- Escenas y niveles:
  - `scenes/levels/act1/criogenia.tscn`: instancia `Environment.tscn`, malla de escenario, `SpawnPoint`, `PuzzleZone` con `MovingPlatform` y `Conveyor`.
  - `scenes/common/Environment.tscn`: efectos globales (fog/glow) compartidos.
- Plataformas y entorno dinámico:
  - `scenes/common/MovingPlatform.tscn` + `scripts/MovingPlatform.gd` (plataforma A↔B con `speed` y `wait_time`).
  - `scenes/common/Conveyor.tscn` + `scripts/Conveyor.gd` + `materials/conveyor/ConveyorStripe.tres`.
- Gestión global:
  - `autoload/PlayerManager.gd`: spawn/respawn y posicionamiento via `SpawnPoint`.
- Addons/Plugins:
  - `addons/simplified_flightsim/`: librería de vuelo (GDScript) con ejemplos en `examples/flight_sim/`.
  - `addons/kenney_prototype_textures/`: texturas de prototipado.
  - Sin plugins de editor activos.
- Datos y materiales:
  - `data/Curves/*.tres`: curvas de aceleración disponibles para perfiles.
  - `data/odisea_wiki.json`: índice narrativo/diseño para alineación de MVP.

## Controlador del Jugador (PlayerController.gd)
- Base: `KinematicBody` con gravedad, salto, caminar/correr, rodar/dash y ataques placeholder.
- Movimiento:
  - Input WASD → vector relativo a cámara (`$Camroot/h`) → `horizontal_velocity` interpolada por `acceleration`.
  - Aplicación via `move_and_slide(movement, Vector3.UP)` (sin `snap`).
  - Rotación de malla con `lerp_angle` hacia la cámara (al apuntar) o hacia la dirección de movimiento.
- Estados/animación:
  - Flags: `is_walking`, `is_running`, `is_attacking`, `is_rolling` → parámetros en `AnimationTree`.
  - Ataques y roll ajustan aceleración/angular_acceleration.
- Sensado/feedback:
  - `RayCast` hacia suelo para posicionar una “sombra falsa” (MeshInstance con opacidad/escala por distancia).
- Limitaciones actuales:
  - Sin `move_and_slide_with_snap` → menor estabilidad en bordes y plataformas móviles.
  - No existe interfaz de “velocidad externa”/“platform velocity” → plataformas y conveyor no influyen en el desplazamiento del jugador.
  - Sin coyote time ni input buffering de salto/rodar.

## Plataformas Móviles y Conveyor
- `MovingPlatform`:
  - Trayectoria lineal A↔B con ping-pong (`point_a`, `point_b`, `speed`, `wait_time`). Sin `Path/PathFollow` ni `Curve3D`.
  - El script mueve la plataforma; no comunica su velocidad/Δtransform a pasajeros.
- `Conveyor`:
  - `Area` que aplica empuje direccional; requiere que los cuerpos integren una interfaz de velocidad externa para efecto consistente.
- Integración actual:
  - `criogenia.tscn` instancia `MovingPlatform_B` y `Conveyor` en `PuzzleZone`.
- Problemas detectados:
  - Ausencia de transferencia de velocidad → deslizamiento/jitter del jugador sobre plataforma.
  - Sin perfiles de aceleración/easing → movimiento percibido como “mecánico” en arranques/paradas.
  - Sin curvas espaciales → incapacidad para rutas naturales (curvas suaves, S-bends, bucles).

## Limitaciones del Stack (Godot 3 / GLES2)
- GLES2:
  - Luces dinámicas limitadas; materiales/shaders avanzados recortados; precisión de color inferior.
  - Partículas suelen ser CPU o simplificadas; post-proceso restringido.
- Godot 3.x:
  - API basada en `KinematicBody`/`move_and_slide`; migrar a 4.x (`CharacterBody3D`) implica refactor.
  - Físicas en móviles requieren soluciones manuales (snap, platform velocity, Δtransform).
- Export Android:
  - Presets presentes; validar `target_sdk`/firmas. Rendimiento puede requerir downscaling/LOD en GLES2.

## Nivel Actual — Acto I: Criogenia
- Escena: `scenes/levels/act1/criogenia.tscn`.
- Elementos: `EnvironmentEffects`, malla SDE, plataforma base (`CSGBox`), `SpawnPoint` y `PuzzleZone` con una `MovingPlatform` lineal y un `Conveyor`.
- Objetivo MVP: primer puzzle introductorio de sigilo/plataformas, transporte básico con plataforma dinámica y transporte continuo con conveyor.

## Agenda de Investigación — “Satisfying Movement”
1) Transferencia de movimiento de plataforma
- Objetivo: el jugador “viaja con” la plataforma sin jitter.
- Estrategia:
  - Exponer en el jugador `set_external_velocity(vel: Vector3)` y acumular `platform_velocity` por frame.
  - Sumar `platform_velocity` a la `horizontal_velocity` antes de `move_and_slide`.
  - Alternativa/extra: calcular Δtransform de la plataforma (posición y rotación) y aplicarlo parcial al pasajero.
  - Usar `move_and_slide_with_snap` con `snap_vector = -floor_normal * snap_len` para mantener adhesión.

2) Trayectorias curvilíneas de plataformas
- Objetivo: movimiento natural con curvas y easing.
- Estrategia:
  - `Path` + `PathFollow` + `Curve3D` para definir trayectorias.
  - Velocidad constante por arco (re-parametrización por longitud) o `unit_offset` derivado de `Curve` temporal (`Curve` 1D) para ease in/out.
  - Exponer tangente/velocidad instantánea de `PathFollow` para alimentar a pasajeros.

3) Perfiles de aceleración y “feel”
- Objetivo: arranques/paradas suaves y control agradable.
- Estrategia:
  - Usar `data/Curves/*.tres` para perfilar aceleración/damping del jugador y plataformas.
  - Limitar jerk (derivada de aceleración) en cambios bruscos; smoothing exponencial (`lerp`) con límites.

4) Robustez de salto y aterrizaje
- Objetivo: reducir frustración y mejorar respuesta.
- Estrategia:
  - Coyote time (p. ej., 120–150 ms) tras abandonar suelo.
  - Input buffering (p. ej., 120–200 ms) para saltos/rodar antes de aterrizar.
  - Control aéreo limitado y distinto de suelo; fricción/drag diferenciados.

5) Cámara y orientación
- Objetivo: lectura clara de movimiento y precisión.
- Estrategia:
  - Cámara con “spring-damper” (suavizado crítico), corrección de colisiones con paredes y offset dinámico.
  - Giro de personaje hacia velocidad deseada con `lerp_angle` y caps de giro.

6) Conveyor consistente
- Objetivo: empuje uniforme, independiente del frame-rate.
- Estrategia:
  - Normalizar interfaz `set_external_velocity` para KinematicBody y considerar `apply_central_impulse` para RigidBody.
  - Asegurar que la dirección y magnitud se integren por `delta` y no por frame.

7) Rendimiento y determinismo
- Objetivo: comportamiento estable en 60 FPS (desktop) y 30–60 (Android).
- Estrategia:
  - Minimizar cálculo por frame; evitar `get_world().direct_space_state` en loops críticos.
  - Considerar substeps locales para plataformas muy rápidas.

## APIs Propuestas (borrador)
- En `PlayerController.gd`:
```gdscript
var platform_velocity := Vector3()
var snap_len := 0.5

func set_external_velocity(v: Vector3) -> void:
	platform_velocity = v

func _physics_process(delta):
	# ... calcular input -> desired_horizontal
	var hv := desired_horizontal
	# aplicar velocidad externa (plataforma/conveyor)
	hv += platform_velocity
	# snap cuando en suelo
	var on_floor := is_on_floor()
	var snap_vec := on_floor ? -get_floor_normal() * snap_len : Vector3()
	var motion := Vector3(hv.x, vertical_velocity.y, hv.z)
	motion = move_and_slide_with_snap(motion, snap_vec, Vector3.UP, true)
	# decaimiento de velocidad externa por frame
	platform_velocity = platform_velocity.linear_interpolate(Vector3(), clamp(6.0 * delta, 0.0, 1.0))
```
- En `MovingPlatform.gd` (ideas):
```gdscript
# Si usa PathFollow:
var last_origin := Vector3()
func _physics_process(delta):
	# actualizar unit_offset con perfil de velocidad (Curve)
	var vel := (global_transform.origin - last_origin) / delta
	# notificar a cuerpos sobre plataforma (área/overlap) con vel
	last_origin = global_transform.origin
```

## Riesgos y Decisiones Pendientes
- Mantener 3.x/GLES2 para MVP vs migrar a 4.x: se prioriza 3.x por estabilidad del scope.
- Complejidad de curvatura: `PathFollow` simplifica rutas, pero exige cuidado con reparametrización para velocidad constante.
- Interfaz común de “external velocity”: acordar contrato y adoptarlo en jugador, conveyor y plataformas.
- Android: performance en GLES2 puede requerir reducir luces y materiales; evaluar LOD.

## Referencias de Archivos
- Jugador: `players/elias/PlayerController.gd`
- Nivel: `scenes/levels/act1/criogenia.tscn`
- Plataformas: `scenes/common/MovingPlatform.tscn`, `scripts/MovingPlatform.gd`
- Conveyor: `scenes/common/Conveyor.tscn`, `scripts/Conveyor.gd`, `materials/conveyor/ConveyorStripe.tres`
- Autoload: `autoload/PlayerManager.gd`
- Datos: `data/Curves/*.tres`, `data/odisea_wiki.json`
- Export: `export_presets.cfg`, `android/`

---

## Próximos Pasos Sugeridos (para el agente de research)
- Prototipar `Path/PathFollow` con `Curve3D` y perfil de velocidad (`Curve`) para una `MovingPlatform_Curved.tscn`.
- Implementar `set_external_velocity` y `move_and_slide_with_snap` en el jugador; diseñar pruebas A/B sobre plataforma y conveyor.
- Añadir coyote time e input buffering (saltos/rodar) con métricas (tiempos en ms configurables).
- Diseñar cámara spring-damper con límites y colisión contra geometría.
- Preparar benchmarks simples (escena sandbox) para medir jitter/deriva en 60/30 FPS.
