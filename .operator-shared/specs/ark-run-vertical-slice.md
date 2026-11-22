# Ark-Run vertical slice — contrato técnico compartido (FD-324)

Este archivo es la fuente única para los workers F1–F6. Si una tarea necesita
algo distinto, se cambia aquí primero (en la rama de integración) y luego en el
código. Diseño de la experiencia y grafo de tareas: `docs/features/FD-324_del_hub_al_motor.md`.

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
| `HUMAN_AUTOPILOT_MARGIN` | `0.25` | ≥ 25 %. |

Proa = `+Z`, popa = `-Z`. El eje de giro es Z y el origen está en el centro de
la nave. El marco es `SpinFrame` (FD-323): `omega = sqrt(9.8 / 240)`.

## Nombres de nodos de `ArkRunSlice.tscn`

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
├── ExplosionController        (Spatial vacío, F1)
├── TraversalRoot              (Spatial vacío, F2)
├── IndustryRoot               (Spatial vacío, F3)
├── EngineIgnitionRoot         (Spatial vacío, F5)
└── RaceHudRoot                (Spatial vacío, F4)
```

No se agregan `WorldRotator` ni `CylinderRotator`. Los contenedores vacíos se
llenan en su tarea sin renombrarlos ni moverlos.

## Contratos de `ArkRunSlice.gd`

Métodos puros/consultables (estables para F1–F6):

| Método | Semántica |
|--------|-----------|
| `get_spiral_config() -> Dictionary` | Copia de la config de la espiral. |
| `get_slice_length() -> float` | `SLICE_LENGTH`. |
| `get_hull_radius() -> float` | `R_HULL`. |
| `get_hub_radius() -> float` | `R_HUB`. |
| `get_bridge_plate_indices() -> Array` | `[47, 48, 49]`. |
| `get_bridge_z_min() -> float` | `z` de la primera placa de Puente (880). |
| `get_engine_z_max() -> float` | `-940.0`. |
| `zone_at(pos: Vector3) -> String` | `"Motor"` si `z ≤ -940`; `"Puente"` si `z ≥ 880`; `""` si no. |
| `is_in_bridge(pos) -> bool` / `is_in_engine(pos) -> bool` | Azúcar sobre `zone_at`. |
| `spawn_at_hub_start(r0 := 4.0, z0 := 0.0)` | Coloca el Pilot en el hub con `up` de `SpinFrame`. |
| `update_spin_presentation(dt)` | Orienta el rig existente y muestra el predictor. Nunca muta la física. |
| `r_local_for_position(pos) -> float` | Radio de la placa más cercana en `z` (para el predictor). |

## Contratos de `ArkRunHull.gd`

`extends StaticBody`, `class_name ArkRunHull`. Colisión completa e inmutable,
construida una sola vez en `_ready()`:

- Pared: `wall_segments` cajas tangentes cubriendo 360°; cara interior en
  `R_HULL`, solapadas para no dejar rendijas.
- Tapas: `CylinderShape` en `z = ±(SLICE_HALF + cap_extension)` solapadas con la
  pared. Toda caída termina dentro del casco.
- Visual: un `CylinderMesh` sin tapas, `CULL_DISABLED`, alineado al eje Z.

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

## Contratos de gameplay entre módulos

- **Intents, no estado.** Cualquier asistencia (autopiloto TAB) sólo escribe
  `move_vec`, `sprint`, `jump` en `InputDataV2`. Nunca velocidad, transform ni
  cámara.
- **Señales sólo para efectos no físicos.** Sonido, animación, HUD. El estado
  físico se actualiza en `_physics_process`.
- **Reinicio instantáneo.** Rearmar = recargar `ArkRunSlice` o resetear estado
  determinista; nada de esperar animaciones.
- **Fantasma = replay de posiciones.** Se reproduce desde el stream grabado; no
  re-ejecuta el autopiloto ni la física asistida.
- **Compatibilidad.** `SPIN_REAL` sigue opt-in; los modos 0..3 y
  `test_determinism_v2` no cambian.

## Grafo de dependencias

```
F0 (base: SpinFrame axial + ArkRunSlice + ArkRunHull + zonas)
 ├── F1 (explosión/lanzamiento)      ─┐
 ├── F2 (carrera espiral/cuerda)      │
 │    └── F3 (zona industrial)        ├── F6 (meta + validación)
 └── F4 (autopiloto/HUD/fantasma)     │
      └── F5 (ignición a_axial)       ─┘
```

F2 y F3 no tocan `ArkRunHull.gd`, `SpinFrame.gd` ni el predictor. F5 consume
`a_axial` ya expuesto por F0 y no lo reimplementa. F6 integra todo y no reescribe
los módulos de F1–F5.

## Verificación focalizada

```bash
python3 -m pytest tests/test_odisea_runner.py -k "test_spin_frame or test_spin_real_camera or test_ark_run_base or test_spin_lab_base"
```

Cada tarea F1–F6 agrega su propio test y lo corre antes de pedir integración.
