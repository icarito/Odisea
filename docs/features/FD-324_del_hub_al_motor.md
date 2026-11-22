# FD-324: Del hub al motor — vertical slice jugable (Transit-Run)

**Status:** Plan v2 aprobado; F0 implementado (base + medición de performance).
**Priority:** Alta (primer vertical slice completo de física rotante real en gameplay).
**Effort:** Alto (8 tareas F0–F7, integración continua).
**Created:** 2026-11-21
**Revised:** 2026-11-22 (v2: grafo F0–F7, ascensores, Suit OS, rendimiento)
**Depends on:** FD-323 (SpinFrame, `SPIN_REAL`, `DomeSpiralField`, `SpinAxialHubV2`,
`SpinRealCameraController`, `SpinLandingPredictor`).

## 1. Problema

FD-323 dejó la física rotante real (`SPIN_REAL`) validada en una escena aislada
(`SpinLab.tscn`), pero todavía no existe una experiencia de juego que la use de
punta a punta. El jugador no tiene objetivo, cronómetro ni una razón para moverse
por el casco: la física es correcta, pero no es *jugable*.

FD-324 convierte esa base en un **vertical slice de 2–4 minutos**: una carrera
desde el hub axial hasta la sala de motores del Arca, atravesando el casco
giratorio real. Debe demostrar que `SPIN_REAL` sostiene una experiencia completa
(arranque, vuelo, carrera, industria, asistencia, encendido, meta y repetición)
sin tocar `WorldRotator`, `CylinderRotator` ni los modos de gravedad 0..3.

## 2. Experiencia objetivo (2–4 min)

| Acto | Duración aprox. | Qué pasa |
|------|-----------------|----------|
| **1. Inicio ZERO_G en el núcleo** | 10–20 s | El jugador aparece en un núcleo co-rotante con pasamanos: se desplaza por la pared a ~1.6 m/s y agarra con un tirón suave. Sin gravedad centrífuga significativa. |
| **2. Explosión hacia el Puente (+Z)** | 15–25 s de vuelo | Una explosión lo expulsa y lo lanza hacia proa `+Z`. Vuelo libre real (Coriolis incluido), propulsores en LT con Δv limitado, y un aterrizaje grande con slide al llegar al Puente. |
| **3. Recorrido proa → popa** | 60–90 s | Domos variados sobre terrazas, andamios rudimentarios, ascensores radiales deterministas y una zona industrial con cuerda (RT + teclado), spokes y atajos. La cámara 2.5D lee el giro. |
| **4. Encendido de motores** | 3 s de conversión | Al cruzar `z = 0` de regreso (después de haber pasado proa), los motores encienden: `a_axial(t)` sube a 9.8 m/s² en 3 s y se sostiene 30 s. Una animación cinemática corta (sin `RigidBody`) presenta la conversión; las terrazas convierten su marco en 3 s con placas kinemáticas y tracking, y luego conexiones y ascensores se reacoplan o fallan de forma estática determinista. |
| **5. Meta en el Motor** | 10–20 s | El jugador llega al extremo de popa `-Z`. Cronómetro, reinicio instantáneo y fantasma de la mejor corrida. El Suit OS (app Autonavegador) muestra el progreso y los puntos con nombre. |

El cronómetro corre desde la explosión (fin del Acto 1) hasta entrar en la zona
de meta. Reiniciar rearma la escena completa en menos de 1 s.

## 3. Contratos duros

1. **Marco `SpinFrame`, eje Z, sin `WorldRotator` ni `CylinderRotator`.** Toda la
   física del slice vive en el marco canónico de `SpinFrame`. `ArkRunSlice.tscn`
   no instancia rotadores de presentación.
2. **Determinismo de paso fijo.** La simulación corre en `_physics_process(delta)`
   con `delta` fijo (60 Hz). Sin `randf()`, `randomize()`,
   `Engine.get_frames_drawn()` ni tiempo de pared. Mismo input ⇒ mismo resultado.
3. **Física gruesa independiente del streaming.** El casco (`ArkRunHull`) es
   colisión estática, completa e inmutable: 360° + tapas en proa/popa. El arte y
   la industria pueden streamearse, pero la contención nunca depende de contenido
   que entra o sale.
4. **Procedural puro por hash(semilla, coord) con semilla fija publicada:**
   `SLICE_SEED = 32401`. Dos instancias frescas con la misma semilla producen la
   misma geometría, y el orden de carga/streaming no altera el resultado.
5. **`a_axial` por la misma vía `extra_accel`** en `step_free_flight_axial` y en
   `SpinLandingPredictor` (parámetro opcional `a_axial: float = 0.0`). No se crea
   una segunda integración ni se duplica el predictor.
6. **Mismo `CameraRig` / `SpringArm`.** `SpinRealCameraController` sólo orienta el
   rig existente del Pilot. La cámara nunca teletransporta ni rota 180°; la
   inmersión de `AGENTS.md` §2.3 se respeta en cada transición.
7. **Modos 0..3 intactos.** `SPIN_REAL` (`GravityModes.Mode.SPIN_REAL == 4`) es
   opt-in y exclusivo de este slice. `PlayerControllerV2` conserva `Vector3.UP`
   salvo en `SPIN_REAL`, donde usa el `_up` dinámico derivado de `SpinFrame`.
8. **Ascensores radiales deterministas por defecto.** Velocidad 6 m/s, parada de
   3 s en los extremos y posición = función pura del tiempo de simulación. La
   escalera queda sólo como respaldo funcional en `SPIN_REAL`.
9. **Suit OS integrado en slots HUD.** La app Autonavegador vive en
   `core_v2/autoloads/SuitOS.gd`; por defecto R1 = slot 2, L1 sigue
   `player:flashlight`, es reubicable, se usa manteniendo el botón y TAB es el
   atajo de teclado.
10. **Falla estática determinista.** Las conexiones y ascensores que no se
    reacoplan al encender fallan de forma reproducible (misma semilla/estado ⇒
    mismas fallas). No hay aleatoriedad en gameplay.
11. **Conversión con placas kinemáticas + tracking.** La conversión de terrazas
    (3 s) mueve placas kinemáticas; en `SPIN_REAL` el jugador las sigue con el
    tracking de plataformas de `AGENTS.md` §5.2, sin teletransporte ni reseteo de
    velocidad.
12. **Cámara, sombra y LOD.** Vistas cilíndricas en `CameraRig`/`SpringArm`,
    sombra falsa a lo largo de `g_eff`, LOD de 3 niveles (sector horneado /
    MultiMesh / pool cercano). Nada de esto toca la simulación.
13. **Replay y fantasma.** El fantasma se reproduce desde el stream grabado; el
    replay no ejecuta el autopiloto. El `.oys` completo de F7 guarda un hash que
    CI compara.

## 4. Decisiones `[DECIDIR]` (v2, fijadas)

| # | Decisión | Valor v2 |
|---|----------|----------|
| 1 | Largo del slice `L` | `2000 m` (`z ∈ [-1000, +1000]`; proa `+Z`, popa `-Z`). |
| 2 | Radio del casco `R_hull` | `340 m` (banda industrial monumental de 80 m entre `r=260` y `r=340`). |
| 3 | Perfil de empuje | Rampa lineal a `9.8 m/s²` en `3 s`, sostenida `30 s`. |
| 4 | Disparo del encendido | Cruce de `z = 0` de regreso (hacia `-Z`), tras haber pisado/pasado proa. |
| 5 | Duración de conversión de terrazas | `3 s`. |
| 6 | Controles de vuelo/travesía | LT = propulsores (Δv limitado); RT = cuerda (teclado equivalente). |
| 7 | Margen humano vs autopiloto | `≥ 25 %`. |
| 8 | Presupuesto de performance | PC `60 fps`; Android `30 fps`; web `30 fps`. |
| 9 | Transición al estado estático | Animación cinemática corta sin `RigidBody` antes de pasar al estado estático. |
| 10 | Ascensores radiales | `6 m/s`, parada de `3 s` en extremos; posición = `f(t_sim)`. |

## 5. Geometría base del slice

- Espiral: `turns = 2.0`, `total_height = 2000.0`, `plate_step = 40.0`,
  `r_min = 220.0`, `r_max = 260.0`, `phase = 0.0`.
  `plate_count = round(2000 / 40) = 50` placas; `z` de la placa `i` es
  `-1000 + 40·i`, así que cubre `z ∈ [-1000, +960]`.
- Hub axial: `SpinAxialHubV2` sobre el eje Z, `hub_radius = 8.0`,
  `z_min = -1000`, `z_max = 1000`. Punto de inicio en `z ≈ 0`.
- Núcleo co-rotante con pasamanos (F1) alrededor del hub: pared a ~1.6 m/s y
  agarre con tirón suave.
- Casco: `ArkRunHull` en `R_hull = 340`, largo `2000`, tapas en `+1020` y `-1020`;
  banda industrial de 80 m entre `r=260` y `r=340`.
- Ascensores radiales (F2): 6 m/s, 3 s en extremos, posición pura de `t_sim`.
- Zonas declaradas y consultables por posición:
  - **Puente** (`+Z`): últimas placas de proa, índices `47..49` (`z ≥ 880`).
  - **Motor** (`-Z`): extremo de popa, `z ≤ -940`.
  - **Núcleo**: hub axial en `z ≈ 0`, dentro de `r ≤ 8`.
- Contenedores base (F0): `ExplosionController`, `TraversalRoot`,
  `IndustryRoot`, `EngineIgnitionRoot`, `RaceHudRoot`. Cada tarea agrega sus
  nodos dentro de su contenedor; no los renombra ni los mueve.

## 6. Grafo de tareas F0–F7

Integración: `ao/ark-run/integration` (merge `--no-ff` por tarea cuando sus tests
focalizados estén verdes). Cada tarea trabaja en su rama y no toca los archivos
prohibidos del slice.

### F0 — Base (rama `ao/ark-run/f0-base`) — implementado

- **Depende de:** FD-323.
- **Objetivo:** marco axial, casco grueso, escena base, zonas y medición base de
  performance.
- **Hecho:**
  - `SpinFrame`: `a_axial_vec`, `g_eff`, `up_eff`, `step_free_flight_axial`.
  - `SpinLandingPredictor`: `a_axial` opcional por `extra_accel`.
  - `ArkRunHull`: colisión 360° + tapas, malla visual ligera.
  - `ArkRunSlice.tscn/.gd`: 50 placas, hub en `z≈0`, zonas Puente/Motor,
    contenedores F1–F5, sin rotadores.
  - `AGENTS.md` §5.1: excepción `SPIN_REAL`.
- **Confirmación de plataforma:** Sebastián confirmó que el fork Box3D `v0.5.4`
  compila y corre en **Android** y **HTML5**. El repo fija hoy `v0.5.7` (usado
  para la medición base de §7).
- **Archivos permitidos:** los de F0 (`SpinFrame.gd`,
  `SpinLandingPredictor.gd`, `core_v2/levels/ark_run/*`,
  `test_spin_frame.gd`, `test_ark_run_base.gd`, `AGENTS.md` §5.1,
  `project.godot` sólo `class_name`).
- **Prohibidos:** `WorldRotator.gd`, `CylinderRotator.gd`, `OdiseaExterior.*`,
  `ScaffoldOrbit.tscn`, `TerraceSpiral.gd`, `SpinLab.tscn`, `agents/`, ANNA,
  formato `.oys`.
- **Test mínimo:** `test_spin_frame` (axial + predictor) y `test_ark_run_base`
  (carga, zonas, contención Box3D).
- **Aceptación:** escena carga headless sin rotadores; `L=2000`, `R_hull=340`,
  hub en `z≈0`; cuerpo lanzado radialmente más allá de `r=260` impacta el casco
  en `r≈340`; medición base registrada (§7).

### F1 — Inicio y explosión (rama `ao/ark-run/f1-launch`)

- **Depende de:** F0.
- **Objetivo:** arranque ZERO_G en núcleo co-rotante con pasamanos y eyección al
  Puente con vuelo de 15–25 s.
- **Alcance:**
  - Núcleo co-rotante con pasamanos: desplazamiento por pared a ~1.6 m/s y
    agarre con tirón suave.
  - Explosión hacia `+Z`; ventana de vuelo 15–25 s.
  - Propulsores en LT con Δv limitado (intents, no estado).
  - Aterrizaje grande en el Puente con slide.
- **Archivos permitidos:** `core_v2/levels/ark_run/ExplosionLaunchV2.gd`,
  `CoreHandrailV2.gd`, `ExplosionController`, `ArkRunSlice.gd`/`.tscn`, tests de
  F1.
- **Prohibidos:** los de F0 más `SpinFrame.gd`, `SpinLandingPredictor.gd`,
  `ArkRunHull.gd`, `WorldRotator.gd`, `CylinderRotator.gd`, `.oys`.
- **Test mínimo:** eyección dentro de 15–25 s con llegada a Puente; Δv acotado;
  pasamanos a ~1.6 m/s con agarre suave; determinismo de dos corridas.
- **Aceptación:** mismo input ⇒ mismo punto de llegada (`drift == 0`); sin
  teletransporte ni salto de cámara.

### F2 — Recorrido (rama `ao/ark-run/f2-traversal`) — paralelo tras F0

- **Depende de:** F0 (paralelo con F1, F3, F4).
- **Objetivo:** recorrido completo con domos variados, andamios, ascensores y
  cuerda, y una ruta canónica proa→popa para `AutopilotInputV2`.
- **Alcance:**
  - Domos variados sobre terrazas.
  - Andamios rudimentarios alrededor de los domos.
  - **Ascensores radiales deterministas por defecto**: `6 m/s`, parada `3 s` en
    extremos, posición = función pura del tiempo de simulación. La escalera es
    sólo respaldo funcional en `SPIN_REAL`.
  - Cuerda en RT + teclado (adjuntar/soltar conservando momento).
  - Ruta canónica proa→popa con waypoints estables para `AutopilotInputV2`.
- **Archivos permitidos:** `core_v2/levels/ark_run/Traversal*`, `Elevator*`,
  `Rope*`, `TraversalRoot`, `ArkRunSlice.gd`/`.tscn`, tests de F2.
- **Prohibidos:** `ArkRunHull.gd`, `SpinFrame.gd`, `SpinLandingPredictor.gd`,
  `ExplosionLaunchV2.gd`, `WorldRotator.gd`, `CylinderRotator.gd`, `.oys`.
- **Test mínimo:** posición de ascensor = `f(t_sim)` (dos corridas idénticas);
  parada de 3 s en extremos; recorrido completo sin atascos; cuerda conserva
  momento; waypoints canónicos; escalera de respaldo funciona.
- **Aceptación:** recorrido proa→popa sin caer fuera del casco; cámara 2.5D sin
  parpadeo; autopiloto puede seguir la ruta canónica.

### F3 — Industria procedural (rama `ao/ark-run/f3-industry`) — paralelo tras F0

- **Depende de:** F0 (paralelo con F1, F2, F4).
- **Objetivo:** racimos industriales deterministas con conectores y modos de
  gravedad, streaming y colisión gruesa siempre presente.
- **Alcance:**
  - Racimos deterministas por `hash(SLICE_SEED, coord)` con conectores y modos de
    gravedad.
  - Streaming de arte/detalle; **colisión gruesa siempre presente**.
  - Test de independencia del orden de carga/streaming.
- **Archivos permitidos:** `core_v2/levels/ark_run/Industry*`, `IndustryRoot`,
  `ArkRunSlice.gd`/`.tscn`, tests de F3.
- **Prohibidos:** `ArkRunHull.gd`, `SpinFrame.gd`, `SpinLandingPredictor.gd`,
  `Traversal*`, `Elevator*`, `WorldRotator.gd`, `CylinderRotator.gd`, `.oys`.
- **Test mínimo:** misma semilla ⇒ mismos racimos y conectores; resultado
  idéntico con dos órdenes de carga/streaming; la colisión gruesa existe antes y
  después del streaming.
- **Aceptación:** la ruta principal sigue siendo completable; el streaming no
  cambia física ni determinismo.

### F4 — Suit OS (rama `ao/ark-run/f4-suitos`) — paralelo tras F0

- **Depende de:** F0 (paralelo con F1, F2, F3).
- **Objetivo:** app Autonavegador en `core_v2/autoloads/SuitOS.gd`, mini mapa,
  gravedad local y destinos.
- **Alcance:**
  - App Autonavegador en slot HUD: default **R1 = slot 2**, **L1 sigue
    `player:flashlight`**, reubicable, mantener para usar, **TAB** atajo teclado.
  - Mini mapa del cilindro: corte radial + barra proa↔popa `z`.
  - Gravedad local: magnitud `g` + flecha efectiva (`g_eff`).
  - Destino propuesto + lista de puntos con nombre: Puente, Núcleo, Motor,
    ascensores.
  - Aviso de encendido de motores.
- **Archivos permitidos:** `core_v2/autoloads/SuitOS.gd`,
  `core_v2/ui/suit_os/*`, `RaceHudRoot`, `ArkRunSlice.gd`/`.tscn`, tests de F4.
- **Prohibidos:** `WorldRotator.gd`, `CylinderRotator.gd`, `SpinFrame.gd`,
  formato `.oys`, `ArkRunHull.gd`.
- **Test mínimo:** defaults de slots y reubicación; mantener-para-usar; mapeo del
  mini mapa (corte y barra `z`); vector de gravedad local; aviso de encendido.
- **Aceptación:** R1/L1 no rompen el HUD existente; la app es usable con teclado
  y mando; el mini mapa no altera la simulación.

### F5 — Encendido de motores (rama `ao/ark-run/f5-ignition`)

- **Depende de:** F2 y F3.
- **Objetivo:** encendido al cruzar `z=0` de regreso, conversión de terrazas con
  animación cinemática corta sin `RigidBody`, y reacople/falla estática.
- **Alcance:**
  - Rampa `a_axial(t)` a `9.8 m/s²` en `3 s`, sostenida `30 s`, al cruzar `z=0`
    de regreso después de haber pasado proa.
  - Aviso Suit OS + audio + predictor analítico axial.
  - Conversión de terrazas en `3 s` con placas kinemáticas y tracking de
    plataformas (`AGENTS.md` §5.2) en `SPIN_REAL`, precedida por una animación
    cinemática corta sin `RigidBody`.
  - Reacople y **falla estática determinista** de conexiones y ascensores.
- **Archivos permitidos:** `core_v2/levels/ark_run/EngineIgnition*`,
  `EngineIgnitionRoot`, `ArkRunSlice.gd`/`.tscn`, tests de F5.
- **Prohibidos:** `SpinFrame.gd` (ya expone `a_axial`), `SpinLandingPredictor.gd`
  (ya acepta `a_axial`), `ArkRunHull.gd`, `WorldRotator.gd`,
  `CylinderRotator.gd`, `.oys`.
- **Test mínimo:** disparo sólo con `prev_z > 0 ∧ z ≤ 0` tras pasar proa; curva
  rampa/hold; placas kinemáticas mueven al jugador con tracking; fallas estáticas
  reproducibles; predictor axial coincide con la simulación.
- **Aceptación:** la conversión no teletransporta ni rota 180° la cámara; el
  jugador conserva posición y velocidad; mismas fallas con el mismo estado.

### F6 — Carrera y presentación (rama `ao/ark-run/f6-presentation`)

- **Depende de:** F1, F2 y F4.
- **Objetivo:** cronómetro, reinicio, fantasma, presentación cilíndrica y LOD.
- **Alcance:**
  - Cronómetro, reinicio instantáneo y fantasma desde replay.
  - Vistas cilíndricas en `CameraRig`/`SpringArm`.
  - Sombra falsa a lo largo de `g_eff`.
  - LOD de 3 niveles: sector horneado / MultiMesh / pool cercano.
  - Pase visual Tron y assets provisionales reemplazables por kit Blender.
  - **Presupuesto de presentación:** acotar horizonte/cadencia del predictor
    (coste dominante de la medición F0, §7) para sostener PC 60 y habilitar
    Android/web 30.
- **Archivos permitidos:** `core_v2/levels/ark_run/Race*`, `Presentation*`,
  `RaceHudRoot`, `core_v2/camera/*` (sólo presentación), `ArkRunSlice.gd`/`.tscn`,
  tests de F6.
- **Prohibidos:** `SpinFrame.gd`, `ArkRunHull.gd`, `Traversal*`, `Elevator*`,
  `Industry*`, `EngineIgnition*`, `WorldRotator.gd`, `CylinderRotator.gd`, `.oys`.
- **Test mínimo:** cronómetro/reinicio/fantasma deterministas; transiciones de
  LOD sin popping (histéresis); sombra en dirección `-g_eff`; presupuesto de
  performance verde con el predictor acotado; continuidad de cámara.
- **Aceptación:** corrida completa con cronómetro y fantasma; sin cortes de
  cámara; FPS dentro del presupuesto de §4.

### F7 — Validación integrada (rama `ao/ark-run/f7-validation`) — último

- **Depende de:** F5 y F6 (y por transitividad F0–F4).
- **Objetivo:** validar el slice completo con `.oys`, hash en CI y performance
  multiplataforma.
- **Alcance:**
  - `.oys` completo de los 5 actos con **hash guardado y comparado en CI**.
  - Medición de performance en PC/Android/web.
  - Checklist de playtest.
- **Archivos permitidos:** `core_v2/levels/ark_run/*.oys`, `core_v2/tests/*`,
  `.github/workflows/*` (job de hash), documentación de playtest.
- **Prohibidos:** reescribir módulos de F0–F6; `WorldRotator.gd`,
  `CylinderRotator.gd`.
- **Test mínimo:** dos instancias frescas producen el mismo hash (`drift == 0`);
  CI compara el hash; tabla de performance PC/Android/web; checklist firmado.
- **Aceptación:** experiencia de 2–4 min sin glitches; reinicio `< 1 s`; hash
  estable en CI; presupuestos de §4 medidos en las tres plataformas.

### Dependencias

```text
F0 ─┬─ F1 ──────────────┐
    ├─ F2 ─┬─ F5 ───────┤
    ├─ F3 ─┘            ├─ F6 ─ F7
    └─ F4 ──────────────┘
```

F1, F2, F3 y F4 pueden correr en paralelo tras F0. F5 espera F2 y F3. F6 espera
F1, F2 y F4. F7 cierra todo.

## 7. Performance base (F0)

**Fecha:** 2026-11-22. **Binario:** fork Box3D `v0.5.7`, Godot
`3.6.4-rc custom_build 22957f59` (binarios dev, no un export release).
**Escena:** `res://core_v2/levels/ark_run/ArkRunSlice.tscn` recién instanciada,
sin input, con el Pilot en el hub ZERO_G (F0). **Método:** harness one-off
`SceneTree` (no versionado) que carga la escena, calienta 120 frames, muestrea
300 frames con `target_fps = 60` y vsync off, y combina monitores de
`Performance` con FPS de reloj de pared (`samples / wall_time`). Headless =
binario `platform=server` pinneado; gráfico = X11 `1280x720`, GLES3, Intel Iris
Xe (Mesa). La fila "sin predictor" quita el nodo `SpinLandingPredictor` antes de
correr (es presentación pura; la simulación no cambia) para aislar su coste.

| Configuración | Entorno | wall FPS | process ms | physics ms (avg/max) | draws | objetos | vértices | nodos | memoria | PC 60 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Autoloads only (sin escena) | headless | 60.2 | 1.73 | 0.46 / — | 0 | 0 | 0 | 132 | 58.1 MB | ✅ |
| ArkRun sin predictor | headless | 60.2 | 2.87 | 5.96 / 10.6 | 0 | 0 | 0 | 326 | 61.1 MB | ✅ |
| ArkRun completo (idle en hub) | headless | 57.0 | 1.77 | 25.5 / 30.7 | 0 | 0 | 0 | 329 | 61.1 MB | ❌ |
| ArkRun sin predictor | GUI 1280×720 | 59.5 | 18.9 | 5.34 / 6.45 | 8 | 7 | 30 660 | 326 | 63.8 MB | ✅ |
| ArkRun completo (idle en hub) | GUI 1280×720 | 52.2 | 11.4 | 25.7 / 35.4 | 10 | 8 | 160 548 | 329 | 63.9 MB | ❌ |

`fps_avg` del monitor en la corrida GUI completa: 53.5 (mín. 47); sin predictor:
59.5 (mín. 57). La corrida headless completa varió 55–59 wall FPS según carga
del host; la tabla reporta una corrida representativa.

### Presupuesto por plataforma

| Plataforma | Presupuesto | Base geometría (sin predictor) | Base idle completa | Estado |
|---|---|---|---|---|
| PC | 60 fps | 59.5 GUI / 60.2 headless | 52.2 GUI / 57.0 headless | Geometría ✅; idle ❌ → F6 |
| Android | 30 fps | no medido en device | no medido | Pendiente F7 |
| Web | 30 fps | no medido en device | no medido | Pendiente F7 |

### Hallazgos

1. **El coste dominante es el predictor de aterrizaje.** Pasar de completo a sin
   predictor baja physics de `25.5 → 6.0 ms` (headless) y de `25.7 → 5.3 ms`
   (GUI), y los vértices de `160 548 → 30 660`. El predictor recorre hasta 1800
   pasos por frame de física mientras el Pilot está en vuelo en gravedad casi
   nula (el hub ZERO_G de F0); no es un caso típico de gameplay, pero es el
   *idle worst case* de la escena base.
2. **La base de geometría y física es sana en PC.** ~5.3–6.0 ms de physics, 8
   draw calls, 30.7k vértices y ~59.5 fps a 1280×720. No está limitada por draw
   calls.
3. **La escena completa en idle no sostiene PC 60** (52.2 wall / 53.5 fps_avg).
   Se registra como línea base, no como presupuesto verde. Mitigación asignada a
   **F6**: acotar horizonte y/o cadencia del predictor (presentación pura, sin
   tocar determinismo), y **F7** re-mide.
4. **Android y web no se midieron en device en esta sesión.** La base de
   geometría tiene margen contra 33 ms (30 fps), pero el hotspot del predictor
   debe acotarse antes de declarar 30 fps; F7 es dueño de la medición en device.
5. **Los monitores no siempre coinciden con el reloj de pared** bajo catch-up de
   física: `physics_ms` puede verse mayor que el frame time. El FPS de reloj de
   pared es la métrica primaria de presupuesto; los monitores son diagnóstico.

Comandos del harness (one-off, no versionado):

```bash
<godot-v0.5.7-headless> --path . --script /tmp/kilo/ark_perf.gd --headless --audio-driver Dummy
<godot-v0.5.7-editor>   --path . --script /tmp/kilo/ark_perf.gd --resolution 1280x720 --audio-driver Dummy
```

## 8. Riesgos

| Riesgo | Mitigación |
|--------|------------|
| Física gruesa incompleta deja caer al jugador fuera del mundo | Casco 360° + tapas solapadas, testeado con un cuerpo real en Box3D (F0). |
| Streaming y física se desincronizan | La colisión del casco y la gruesa son estáticas; sólo el arte se streamea. |
| `a_axial` duplica matemática | Una sola vía: `step_free_flight_axial` delega en `extra_accel`; el predictor usa lo mismo. |
| Ascensores no deterministas | Posición = función pura de `t_sim`; sin aleatoriedad; test de dos corridas. |
| Autopiloto altera el momentum | Sólo escribe intents; el replay no ejecuta el autopiloto. |
| Regresión en modos 0..3 | `SPIN_REAL` sigue opt-in; `test_determinism_v2` y tests focalizados por tarea. |
| Predictor con horizonte completo domina el frame | Acotar horizonte/cadencia en F6; re-medir en F7. |
| Android/web sin medir en device | F7 mide PC/Android/web contra `60/30/30`; la base F0 sólo mide PC. |
| Conversión de terrazas desprende al jugador | Placas kinemáticas + tracking de plataformas (`AGENTS.md` §5.2), testeado en F5. |
| Conflictos de slot HUD | Defaults R1=slot 2 / L1=`player:flashlight`, reubicable y testeado en F4. |

## 9. Verificación global

```bash
python3 -m pytest tests/test_odisea_runner.py -k "test_spin_frame or test_spin_real_camera or test_ark_run_base or test_spin_lab_base"
```

Criterios de cierre: todos los tests focalizados verdes, `test_determinism_v2`
sin drift en el slice, `.oys` de F7 con hash estable en CI, y capturas/playtest
de los 5 actos aprobados por Sebastián.
