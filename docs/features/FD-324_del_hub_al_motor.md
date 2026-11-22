# FD-324: Del hub al motor — vertical slice jugable (Transit-Run)

**Status:** Plan aprobado; F0 (base) en implementación.
**Priority:** Alta (primer vertical slice completo de física rotante real en gameplay).
**Effort:** Alto (5 actos, 7 tareas, integración continua).
**Created:** 2026-11-22
**Depends on:** FD-323 (SpinFrame, `SPIN_REAL`, `DomeSpiralField`, `SpinAxialHubV2`,
`SpinRealCameraController`, `SpinLandingPredictor`).

## 1. Problema

FD-323 dejó la física rotante real (`SPIN_REAL`) validada en una escena aislada
(`SpinLab.tscn`), pero todavía no existe una experiencia de juego que la use de
punta a punta. El jugador no tiene un objetivo, un cronómetro ni una razón para
moverse por el casco: la física es correcta, pero no es *jugable*.

FD-324 convierte `SpinLab` en un **vertical slice de 2–4 minutos**: una carrera
desde el hub axial hasta la sala de motores del Arca, atravesando el casco
giratorio real. Debe demostrar que `SPIN_REAL` sostiene una experiencia completa
(arranque, vuelo, carrera, peligros, asistencia, meta y repetición) sin tocar
`WorldRotator`, `CylinderRotator` ni los modos de gravedad 0..3.

## 2. Experiencia objetivo (2–4 min)

| Acto | Duración aprox. | Qué pasa |
|------|-----------------|----------|
| **1. Inicio ZERO_G en el hub** | 10–20 s | El jugador aparece en la columna axial, sin gravedad centrífuga. Un evento narrativo (alarma/fallo) prepara la eyección. |
| **2. Explosión hacia el Puente (+Z)** | 15–25 s de vuelo | Una explosión lo expulsa radialmente y lo lanza hacia proa `+Z`. Vuelo libre real (Coriolis incluido) hasta el Puente. |
| **3. Carrera proa → popa** | 60–90 s | Recorrido por la espiral del casco (50 placas) y una zona industrial con cuerda, spokes y atajos. La cámara 2.5D lee el giro. |
| **4. Encendido de motores** | 4 s de conversión | Al cruzar `z = 0` de regreso (después de haber pasado proa), se encienden los motores: aparece gravedad axial `a_axial` y las terrazas convierten su marco en 4 s. |
| **5. Meta en el Motor** | 10–20 s | El jugador llega al extremo de popa `-Z`. Cronómetro, reinicio instantáneo y fantasma de la mejor corrida. |

El cronómetro corre desde la explosión (fin del Acto 1) hasta entrar en la zona
de meta. Reiniciar rearma la escena completa en menos de 1 s.

## 3. Contratos duros

1. **Marco `SpinFrame`, eje Z, sin `WorldRotator` ni `CylinderRotator`.** Toda la
   física del slice vive en el marco canónico de `SpinFrame`. `ArkRunSlice.tscn`
   no instancia rotadores de presentación.
2. **Determinismo de paso fijo.** Toda la simulación de gameplay corre en
   `_physics_process(delta)` con `delta` fijo (60 Hz). Sin `randf()`,
   `randomize()`, `Engine.get_frames_drawn()` ni tiempo de pared. El mismo input
   produce el mismo resultado; el fantasma es un replay de posiciones.
3. **Física gruesa independiente del streaming.** El casco (`ArkRunHull`) es
   colisión estática, completa e inmutable: 360° de pared + tapas en proa/popa,
   construida una sola vez. La geometría visual/detallada puede streamearse, pero
   la contención física nunca depende de contenido que entra o sale.
4. **Procedural puro por hash(semilla, coord) con semilla fija publicada.**
   `SLICE_SEED = 32401`. No hay estado global mutable para generar la ruta; dos
   instancias frescas con la misma semilla producen la misma geometría.
5. **`a_axial` por la misma vía `extra_accel`** en `step_free_flight_axial` y en
   `SpinLandingPredictor` (parámetro opcional `a_axial: float = 0.0`). No se crea
   una segunda integración ni se duplica el predictor.
6. **Mismo `CameraRig` / `SpringArm`.** `SpinRealCameraController` sólo orienta el
   rig existente del Pilot. La cámara nunca teletransporta ni rota 180°; la
   inmersión de `AGENTS.md` §2.3 se respeta en cada transición.
7. **Modos 0..3 intactos.** `SPIN_REAL` (`GravityModes.Mode.SPIN_REAL == 4`) es
   opt-in y exclusivo de este slice. `PlayerControllerV2` conserva `Vector3.UP`
   salvo en `SPIN_REAL`, donde usa el `_up` dinámico derivado de `SpinFrame`.

## 4. Decisiones `[DECIDIR]` (fijadas con default)

| # | Decisión | Default |
|---|----------|---------|
| 1 | Largo del slice `L` | `2000 m` (`z ∈ [-1000, +1000]`; proa `+Z`, popa `-Z`). |
| 2 | Radio del casco `R_hull` | `300 m`. |
| 3 | Perfil de empuje | Rampa lineal a `9.8 m/s²` en `3 s`, sostenida `30 s`. |
| 4 | Disparo del encendido | Al cruzar `z = 0` de regreso (hacia `-Z`), tras haber pisado/pasado proa. |
| 5 | Duración de conversión de terrazas | `4 s`. |
| 6 | `nav_assist` (autopiloto) | Sostener (teclado TAB + botón de mando; `AutopilotInputV2` sólo escribe intents). |
| 7 | Margen humano vs autopiloto | `≥ 25 %` (el autopiloto nunca supera al humano por más de ese margen). |
| 8 | Export HTML5 | Fuera de alcance. |

## 5. Geometría base del slice

- Espiral: `turns = 2.0`, `total_height = 2000.0`, `plate_step = 40.0`,
  `r_min = 220.0`, `r_max = 260.0`, `phase = 0.0`.
  `plate_count = round(2000 / 40) = 50` placas; `z` de la placa `i` es
  `-1000 + 40·i`, así que cubre `z ∈ [-1000, +960]`.
- Hub axial: `SpinAxialHubV2` sobre el eje Z, `hub_radius = 8.0`,
  `z_min = -1000`, `z_max = 1000`. Punto de inicio en `z ≈ 0`.
- Casco: `ArkRunHull` en `R_hull = 300`, largo `2000`, tapas en `+1020` y `-1020`.
- Zonas declaradas y consultables por posición:
  - **Puente** (`+Z`): últimas placas de proa, índices `47..49` (`z ≥ 880`).
  - **Motor** (`-Z`): extremo de popa, `z ≤ -940`.
- Contenedores vacíos para F1–F5: `ExplosionController`, `TraversalRoot`,
  `IndustryRoot`, `EngineIgnitionRoot`, `RaceHudRoot`.

## 6. Grafo de tareas

Integración: `ao/ark-run/integration` (merge `--no-ff` por tarea cuando sus tests
focalizados estén verdes). Cada tarea trabaja en su rama y no toca los archivos
prohibidos del slice.

### F0 — Base (rama `ao/ark-run/f0-base`)

- **Objetivo:** marco axial, casco grueso, escena base y zonas.
- **Archivos permitidos:** `core_v2/systems/SpinFrame.gd`,
  `core_v2/camera/SpinLandingPredictor.gd`,
  `core_v2/levels/ark_run/*`, `core_v2/tests/test_spin_frame.gd`,
  `core_v2/tests/test_ark_run_base.gd`, `AGENTS.md` §5.1,
  `project.godot` (sólo `class_name` si hace falta).
- **Prohibidos:** `WorldRotator.gd`, `CylinderRotator.gd`, `OdiseaExterior.*`,
  `ScaffoldOrbit.tscn`, `TerraceSpiral.gd`, `SpinLab.tscn`, `agents/`, ANNA,
  formato de replay `.oys`.
- **Test mínimo:** `test_spin_frame` (axial exacto + predictor) y
  `test_ark_run_base` (carga, zonas, contención física).
- **Aceptación:** escena carga headless sin rotadores; `L=2000`, `R_hull=300`,
  hub en `z≈0`; un cuerpo lanzado radialmente más allá de `r=260` impacta el
  casco en `r≈300` y no sale del mundo.

### F1 — Explosión y lanzamiento al Puente (rama `ao/ark-run/f1-explosion`)

- **Objetivo:** arranque ZERO_G y eyección hacia `+Z` con vuelo de 15–25 s.
- **Archivos permitidos:** `core_v2/levels/ark_run/ExplosionLaunchV2.gd` (nuevo),
  `core_v2/levels/ark_run/ArkRunSlice.gd`/`.tscn`, tests de F1.
- **Prohibidos:** los de F0 más `SpinFrame.gd`, `SpinLandingPredictor.gd`,
  `ArkRunHull.gd`.
- **Test mínimo:** trayectoria de eyección dentro de la ventana de 15–25 s y
  llegada a la zona Puente; determinismo de dos corridas.
- **Aceptación:** mismo input ⇒ mismo punto de llegada (`drift == 0`); sin
  teletransporte ni salto de cámara.

### F2 — Carrera proa → popa por la espiral (rama `ao/ark-run/f2-traversal`)

- **Objetivo:** recorrido completo de las 50 placas, cuerda y spokes.
- **Archivos permitidos:** `core_v2/levels/ark_run/Traversal*`, `TraversalRoot`,
  `ArkRunSlice.gd`/`.tscn`, tests de F2.
- **Prohibidos:** `ArkRunHull.gd`, `SpinFrame.gd`, `SpinLandingPredictor.gd`,
  `ExplosionLaunchV2.gd`.
- **Test mínimo:** completar la espiral de `z=+960` a `z=-940` sin atascos y con
  anclajes de `DomeRegistry` verificados.
- **Aceptación:** recorrido sin caídas fuera del casco; la cámara 2.5D no
  parpadea; la cuerda conserva momento al soltar.

### F3 — Zona industrial y atajos (rama `ao/ark-run/f3-industry`)

- **Objetivo:** hazards con presión de tiempo, atajos con herramienta y props
  industriales.
- **Archivos permitidos:** `core_v2/levels/ark_run/Industry*`, `IndustryRoot`,
  `ArkRunSlice.gd`/`.tscn`, tests de F3.
- **Prohibidos:** los de F2 más `Traversal*`.
- **Test mínimo:** todo atajo es físicamente imposible a pie (barrera
  `≥ 1.20·H_max`) y ningún hazard bloquea la ruta principal.
- **Aceptación:** la ruta principal sigue siendo completable sin herramienta;
  los atajos sólo ahorran tiempo; determinismo preservado.

### F4 — Autopiloto TAB, HUD y fantasma (rama `ao/ark-run/f4-assist`)

- **Objetivo:** `nav_assist` sostenido, cronómetro de carrera y fantasma de la
  mejor corrida.
- **Archivos permitidos:** `core_v2/levels/ark_run/Race*`, `RaceHudRoot`,
  `core_v2/input/AutopilotInputV2.gd` (sólo integración), `ArkRunSlice.gd`/`.tscn`,
  tests de F4.
- **Prohibidos:** `WorldRotator.gd`, `CylinderRotator.gd`, formato de replay
  `.oys`, `SpinFrame.gd`.
- **Test mínimo:** TAB sólo escribe intents (`move_vec`, `sprint`, `jump`); soltar
  devuelve el control en el mismo tick; el fantasma es un replay determinista.
- **Aceptación:** margen humano vs autopiloto `≥ 25 %`; el replay de una corrida
  asistida es indistinguible de uno manual.

### F5 — Encendido de motores y conversión (rama `ao/ark-run/f5-ignition`)

- **Objetivo:** al cruzar `z = 0` de regreso, activar `a_axial` (rampa 9.8 m/s²
  en 3 s, sostenida 30 s) y convertir las terrazas en 4 s.
- **Archivos permitidos:** `core_v2/levels/ark_run/EngineIgnition*`,
  `EngineIgnitionRoot`, `ArkRunSlice.gd`/`.tscn`, tests de F5.
- **Prohibidos:** `SpinFrame.gd` (ya expone `a_axial` desde F0),
  `SpinLandingPredictor.gd`, `WorldRotator.gd`, `CylinderRotator.gd`.
- **Test mínimo:** el encendido sólo dispara con `prev_z > 0 ∧ z ≤ 0` tras haber
  pasado proa; `up_eff` rota hacia `+Z`; el predictor axial coincide con la
  simulación.
- **Aceptación:** la conversión no teletransporta ni rota 180° la cámara; el
  jugador conserva posición y velocidad.

### F6 — Meta, validación y cierre (rama `ao/ark-run/f6-validation`)

- **Objetivo:** meta en Motor, reinicio instantáneo, validación visual y de
  rendimiento del slice completo.
- **Archivos permitidos:** `core_v2/levels/ark_run/ArkRunSlice.gd`/`.tscn`, tests
  de integración de F6, capturas en `test_output/ark_run/`.
- **Prohibidos:** los sistemas de F1–F5 (sólo se integran, no se reescriben).
- **Test mínimo:** corrida completa headless de los 5 actos + determinismo
  (`drift == 0`) + presupuesto de FPS del slice.
- **Aceptación:** experiencia de 2–4 min sin glitches, reinicio `< 1 s`, y
  aprobación visual de Sebastián.

## 7. Riesgos

| Riesgo | Mitigación |
|--------|------------|
| Física gruesa incompleta deja caer al jugador fuera del mundo | Casco 360° + tapas solapadas, testeado con un cuerpo real en Box3D (F0). |
| Streaming y física se desincronizan | La colisión del casco es estática; sólo el arte se streamea. |
| `a_axial` duplica matemática | Una sola vía: `step_free_flight_axial` delega en `extra_accel`; el predictor usa lo mismo. |
| El autopiloto altera el momentum | Sólo escribe intents; el replay no ejecuta el autopiloto. |
| Regresión en modos 0..3 | `SPIN_REAL` sigue siendo opt-in; `test_determinism_v2` y tests focalizados por tarea. |
| Escala y mareo por rotación | Cámara co-rotante y 2.5D con histéresis; validación visual en cada tarea. |

## 8. Verificación global

```bash
python3 -m pytest tests/test_odisea_runner.py -k "test_spin_frame or test_spin_real_camera or test_ark_run_base or test_spin_lab_base"
```

Criterios de cierre: todos los tests focalizados verdes, `test_determinism_v2`
sin drift en el slice, y capturas de los 5 actos aprobadas por Sebastián.
