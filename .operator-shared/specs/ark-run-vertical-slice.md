# Ark-Run vertical slice — contrato técnico compartido (FD-324 v2)

Este archivo es la fuente única para los workers F1–F7. Si una tarea necesita
algo distinto, se cambia aquí primero (en la rama de integración) y luego en el
código. Diseño de la experiencia, decisiones y grafo completo:
`docs/features/FD-324_del_hub_al_motor.md`.

## Constantes canónicas

| Constante | Valor | Notas |
|-----------|-------|-------|
| `SLICE_SEED` | `32401` | Semilla fija publicada. Nada de `randf()`/`randomize()`. |
| `SLICE_LENGTH` | `2000.0` | Largo del casco; `z ∈ [-1000, +1000]`. |
| `SLICE_HALF` | `1000.0` | `SLICE_LENGTH * 0.5`. |
| `R_HULL` | `300.0` | Radio interior del casco (pared de colisión). |
| `R_HUB` | `8.0` | Radio de la columna axial ZERO_G. |
| `SPIRAL_TURNS` | `2.0` | |
| `SPIRAL_HEIGHT` | `2000.0` | `plate_step = 40.0` ⇒ 50 placas. |
| `SPIRAL_R_MIN` / `SPIRAL_R_MAX` | `220.0` / `260.0` | |
| `SPIRAL_PHASE` | `0.0` | |
| `BRIDGE_PLATE_INDICES` | `[47, 48, 49]` | Últimas placas de proa. |
| `BRIDGE_Z_MIN` | `880.0` | `z` de la placa 47. |
| `ENGINE_Z_MAX` | `-940.0` | Meta (extremo de popa). |
| `ENGINE_IGNITION_Z` | `0.0` | Cruce de regreso hacia `-Z`. |
| `THRUST_ACCEL` | `9.8` m/s² | `a_axial` de ignición. |
| `THRUST_RAMP_SECONDS` | `3.0` | |
| `THRUST_HOLD_SECONDS` | `30.0` | |
| `CONVERSION_SECONDS` | `4.0` | Conversión de terrazas. |
| `CORE_HANDRAIL_SPEED` | `1.6` m/s | Desplazamiento por pared en el núcleo. |
| `ELEVATOR_SPEED` | `6.0` m/s | Ascensor radial por defecto. |
| `ELEVATOR_STOP_SECONDS` | `3.0` | Parada en cada extremo. |
| `HUMAN_AUTOPILOT_MARGIN` | `0.25` | ≥ 25 %. |
| `FPS_BUDGET_PC` | `60` | |
| `FPS_BUDGET_ANDROID` / `WEB` | `30` / `30` | |

Proa = `+Z`, popa = `-Z`. El eje de giro es Z y el origen está en el centro de
la nave. El marco es `SpinFrame` (FD-323): `omega = sqrt(9.8 / 240)`.

## Nombres de nodos de `ArkRunSlice.tscn`

Base F0 (ya existe):

```
ArkRunSlice (Spatial, ArkRunSlice.gd)
├── WorldEnvironment
├── Sun
├── DomeSpiralField            (DomeSpiralField.gd, 1 espiral de 50 placas)
├── ArkRunHull                 (StaticBody, ArkRunHull.gd)
├── AxialHub
│   └── SpinAxialHub           (SpinAxialHubV2.gd, r=8, z∈[-1000,1000])
├── Pilot                      (Pilot_v2.tscn, SPIN_REAL opt-in)
├── SpinRealCamera             (SpinRealCameraController.gd)
├── SpinLandingPredictor       (SpinLandingPredictor.gd)
├── BridgeZone                 (Spatial, zona Puente +Z)
├── EngineZone                 (Spatial, zona Motor -Z)
├── ExplosionController        (Spatial, F1)
├── TraversalRoot              (Spatial, F2)
├── IndustryRoot               (Spatial, F3)
├── EngineIgnitionRoot         (Spatial, F5)
└── RaceHudRoot                (Spatial, F4/F6)
```

Nodos previstos (los crea su tarea, sin renombrar los contenedores):

| Tarea | Nodos |
|-------|-------|
| F1 | `CoreRoot/CoreHandrail_*` bajo `ExplosionController` (o `CoreRoot` si se acuerda en integración). |
| F2 | `TraversalRoot/Domes`, `TraversalRoot/Scaffolds`, `TraversalRoot/Elevators/Elevator_*`, `TraversalRoot/Rope`. |
| F3 | `IndustryRoot/Cluster_*` (arte y colisión gruesa). |
| F4 | `RaceHudRoot/SuitOSHost`, app registrada en `SuitOS.gd`. |
| F5 | `EngineIgnitionRoot/IgnitionDriver`, `KinematicPlatesRoot`. |
| F6 | `RaceHudRoot/Chrono`, `RaceHudRoot/Ghost`, `PresentationRoot` (LOD/sombra). |

No se agregan `WorldRotator` ni `CylinderRotator`.

## Contratos de `ArkRunSlice.gd` (base F0, estables)

| Método | Semántica |
|--------|-----------|
| `get_spiral_config() -> Dictionary` | Copia de la config de la espiral. |
| `get_slice_length() -> float` | `SLICE_LENGTH`. |
| `get_hull_radius() -> float` | `R_HULL`. |
| `get_hub_radius() -> float` | `R_HUB`. |
| `get_bridge_plate_indices() -> Array` | `[47, 48, 49]`. |
| `get_bridge_z_min() -> float` | `880.0`. |
| `get_engine_z_max() -> float` | `-940.0`. |
| `get_engine_ignition_z() -> float` | `0.0`. |
| `zone_at(pos: Vector3) -> String` | `"Motor"` si `z ≤ -940`; `"Puente"` si `z ≥ 880`; `""` si no. |
| `is_in_bridge(pos)` / `is_in_engine(pos)` | Azúcar sobre `zone_at`. |
| `spawn_at_hub_start(r0 := 4.0, z0 := 0.0)` | Coloca el Pilot en el hub con `up` de `SpinFrame`. |
| `update_spin_presentation(dt)` | Orienta el rig existente y muestra el predictor. Nunca muta la física. |
| `r_local_for_position(pos) -> float` | Radio de la placa más cercana en `z`. |

## Contratos de `ArkRunHull.gd`

`extends StaticBody`, `class_name ArkRunHull`. Colisión completa e inmutable,
construida una sola vez en `_ready()`:

- Pared: `wall_segments` cajas tangentes cubriendo 360°; cara interior en
  `R_HULL`, solapadas para no dejar rendijas.
- Tapas: `CylinderShape` en `z = ±(SLICE_HALF + cap_extension)` solapadas con la
  pared. Toda caída termina dentro del casco.
- Visual: un `CylinderMesh` alineado al eje Z, `CULL_DISABLED`.

Getters estables: `get_hull_radius()`, `get_slice_length()`,
`get_wall_segment_count()`, `get_collision_shape_count()`.

## Contratos de `SpinFrame` (extensión F0, congelada)

```gdscript
static func a_axial_vec(a_axial: float) -> Vector3
    # Vector3(0, 0, -a_axial): la gravedad axial empuja hacia popa.

static func g_eff(p, omega, a_axial := 0.0) -> Vector3
    # a_centrif(p, omega) + a_axial_vec(a_axial).

static func up_eff(p, omega, a_axial := 0.0,
                   fallback_up := Vector3.UP,
                   r_eps := DEFAULT_R_EPS) -> Vector3
    # -normalize(g_eff(...)); fallback sólo si |g_eff| < r_eps.

static func step_free_flight_axial(p, v, omega, dt, a_axial := 0.0,
                                   extra_accel := Vector3.ZERO) -> Dictionary
    # step_free_flight(p, v, omega, dt, a_axial_vec(a_axial) + extra_accel).
```

`a_axial` entra por la misma vía `extra_accel` (Strang, medio kick inicial y
final). No hay una segunda integración. Error axial en 30 s `< 1e-4` contra
`z0 + vz0·t - 0.5·a·t²`; el plano XY queda idéntico.

## Contratos de `SpinLandingPredictor`

`predict_landing(...)` y `update_preview(...)` agregan `a_axial: float = 0.0` al
final de la firma (retrocompatible). Internamente usan
`SpinFrame.step_free_flight_axial`. Siguen siendo puros para la simulación.

**Presupuesto:** el predictor es presentación pura. F6 debe acotar su horizonte
y/o cadencia (coste dominante de la medición F0, ver FD §7) sin tocar la
simulación.

## Contratos por módulo nuevo

### Explosión / núcleo (F1)

- `CoreHandrailV2` mueve al jugador por la pared a `CORE_HANDRAIL_SPEED`; el
  agarre es un tirón suave, sin teletransporte ni reseteo de momentum.
- `ExplosionLaunchV2.impulse(state) -> Dictionary` devuelve velocidad/posición de
  eyección; la ventana de llegada al Puente es 15–25 s.
- Propulsores en LT: sólo intents `move_vec`/`sprint`/`jump`; Δv total acotado.
- Aterrizaje en el Puente con slide.

### Ascensores radiales (F2)

```gdscript
# Posición pura del ascensor en función del tiempo de simulación.
static func elevator_position(z0: float, t_sim: float,
                              speed := ELEVATOR_SPEED,
                              stop_seconds := ELEVATOR_STOP_SECONDS) -> float
```

- `6 m/s`, parada `3 s` en `z_min`/`z_max`.
- Sin estado mutable ni aleatoriedad: misma `t_sim` ⇒ misma posición.
- La escalera (`SPIN_REAL`) es sólo respaldo funcional, no la vía por defecto.

### Cuerda (F2)

- RT + teclado; adjuntar/soltar conserva momento.
- La cuerda no altera el estado físico fuera de su restricción de longitud.

### Industria procedural (F3)

- Racimos `hash(SLICE_SEED, coord)` deterministas, con conectores y modos de
  gravedad.
- Streaming sólo de arte/detalle; colisión gruesa siempre presente.
- Mismo resultado con cualquier orden de carga/streaming.

### Suit OS (F4)

- App Autonavegador en `core_v2/autoloads/SuitOS.gd`.
- Defaults HUD: **R1 = slot 2**, **L1 = `player:flashlight`**, reubicable,
  mantener para usar, **TAB** atajo teclado.
- Mini mapa: corte radial + barra proa↔popa `z`.
- Gravedad local: magnitud `g` + flecha de `g_eff`.
- Destino propuesto y puntos con nombre: Puente, Núcleo, Motor, ascensores.
- Aviso de encendido de motores.
- La app no escribe estado físico.

### Encendido (F5)

- Disparo: `prev_z > 0 ∧ z ≤ 0` de regreso, tras haber pasado proa.
- `a_axial(t)`: rampa lineal a `9.8 m/s²` en `3 s`, sostenida `30 s`.
- Conversión de terrazas: `4 s`, placas kinemáticas, tracking de plataformas
  (`AGENTS.md` §5.2) en `SPIN_REAL`.
- Reacople y falla estática determinista de conexiones y ascensores.
- Aviso Suit OS + audio + predictor axial; el predictor debe coincidir con la
  simulación.

### Carrera y presentación (F6)

- Cronómetro, reinicio `< 1 s`, fantasma desde replay (no re-ejecuta autopiloto).
- Vistas cilíndricas en `CameraRig`/`SpringArm`; continuidad de cámara.
- Sombra falsa a lo largo de `-g_eff`.
- LOD de 3 niveles: sector horneado / MultiMesh / pool cercano, con histéresis.
- Pase visual Tron; assets provisionales reemplazables por kit Blender.
- Presupuesto de presentación: acotar predictor para PC 60 / Android 30 / web 30.

## Invariantes de determinismo

- Intents, no estado: la asistencia (TAB) sólo escribe `move_vec`, `sprint`,
  `jump`. Nunca velocidad, transform ni cámara.
- Señales sólo para efectos no físicos (sonido, animación, HUD).
- Todo el estado físico se actualiza en `_physics_process`.
- Reinicio = recargar/resetear estado determinista; sin esperar animaciones.
- Fantasma = replay de posiciones; no ejecuta autopiloto ni física asistida.
- El orden de carga/streaming no cambia geometría, física ni resultados.

## Grafo de dependencias

```text
F0 (base: SpinFrame axial + ArkRunSlice + ArkRunHull + zonas + medición)
 ├── F1 (inicio/explosión)                  ─┐
 ├── F2 (recorrido/ascensores/cuerda)        │
 │    └── F5 (encendido)                     ├── F6 (carrera/presentación) ── F7 (validación)
 ├── F3 (industria procedural) ── F5         │
 └── F4 (Suit OS) ───────────────────────────┘
```

F1–F4 corren en paralelo tras F0. F5 espera F2 y F3. F6 espera F1, F2 y F4. F7
cierra con `.oys` + hash en CI y performance PC/Android/web.

## Performance base

La tabla y los hallazgos de F0 están en `docs/features/FD-324_del_hub_al_motor.md`
§7. Resumen: geometría + física base ≈ 6 ms y ~60 fps en PC; el caso idle con el
predictor en horizonte completo es el coste dominante y F6 debe acotarlo antes de
declarar Android/web 30 fps.

## Verificación focalizada

```bash
python3 -m pytest tests/test_odisea_runner.py -k "test_spin_frame or test_spin_real_camera or test_ark_run_base or test_spin_lab_base"
```

Cada tarea F1–F7 agrega su propio test y lo corre antes de pedir integración.
