# FD-269: Room3D — Estado ambiental por habitación (temperatura, presión, contaminación)

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-18
**Parent:** FD-255 (maestro) / FD-256 (criocoolant) / FD-258 (atmósfera) / FD-264 (grafo coolant) / FD-265 (lab) / FD-266 (semántica del puzle)

## Problem

El laboratorio de FD-265 ya tiene las piezas (fuga, tanque, manómetro, gloo, ductos),
pero **no hay un estado ambiental que las amarre**. Cada sistema vive en su propia
máquina de estados y nadie lee "cómo está la sala". Resultado:

- El hielo (`IceLevel`) no tiene de dónde salir ni por qué crecer: no hay temperatura.
- La niebla (`CoolantFogAdapter` / `GasArea3D`) no tiene umbral de contaminación que la
  dispare ni que la haga dañina.
- La presión (`PressureSection`) y el vapor no comparten un mismo valor de sala, así que
  "evaporar el hielo y ventilar por los ductos" no tiene un valor que subir y bajar.

Lo que falta es **una capa ambiental por habitación** que los sistemas lean y escriban:
tres variables, con umbrales discretos, que convierten "cómo está la sala" en un estado
legible y en consecuencias (hielo, daño, riesgo de explosión). Sin ella, el puzle sigue
siendo "cerrar válvula = se arregla" (FD-266) y no un ciclo con tensión.

## Solution

**Room3D** es un nodo `Spatial` que define el volumen de una habitación y posee tres
variables ambientales:

| Variable | Unidad | Qué representa |
|---|---|---|
| `temperature` | °C | Frío que congela (hielo) y, en el extremo, daña |
| `pressure` | bar (nominal ~1.0) | Sobrepresión = riesgo de explosión (FD-258) |
| `contamination` | 0..1 | Fracción de refrigerante/vapor en el aire; ciega y daña |

Room3D **no simula física**. Es un agregador determinista: recibe *deltas* de las fuentes
(fuga, evaporación, ventilación, calefacción), los integra en las tres variables, y emite
señales al cruzar umbrales. Los sistemas *leen* las variables, no las calculan.

### Umbrales discretos (no simulación)

Cada variable cruza pocos umbrales, con nombres que el jugador pueda leer. Los valores son
`export`, calibrables por Sebastián sobre la escena:

**Temperatura** (`temperature`, °C)
- `> freezing_point` (0°C): nominal. Sin hielo, sin daño.
- `<= freezing_point`: **congelando** → `IceLevel` empieza a crecer.
- `<= lethal_cold` (p. ej. -25°C): **daño por frío** al jugador + escarcha densa.

**Contaminación** (`contamination`, 0..1)
- `< fog_threshold` (0.3): aire limpio.
- `>= fog_threshold`: **niebla** → ciega (no daña). Dispara el `CoolantFogAdapter`.
- `>= hazard_threshold` (0.7): **vapor dañino** → `GasArea3D` aplica daño.

**Presión** (`pressure`, bar ~1.0 nominal)
- `<= overpressure` (2.4, igual que `PressureSection.critical_pressure`): nominal.
- `> overpressure`: **riesgo de explosión** → `PressureSection` entra en ciclo de aviso.

### El loop completo (hielo ↔ vapor)

```
FUGA activa
   │  la fuente escribe temperature -= k·leak_intensity
   │                  contamination += k·leak_intensity
   ▼  temperatura cruza freezing_point
HIELO SUBE (IceLevel lee temperature < 0)
   │  sellar la fuga → deja de bajar la temperatura
   ▼
CALENTAR (reactor/calentadores)
   │  temperature sube → el hielo se evapora
   │  contamination sube (vapor)  ← el hielo se convierte en recurso a drenar
   ▼
VENTILAR (ductos, FD-264)
   │  contamination baja, pressure baja
   ▼
SALA ESTABLE
```

**Regla de tensión:** evaporar no es gratis. Si el jugador calienta con los ductos cerrados,
`contamination` trepa a `hazard_threshold` y el vapor le hace daño. La secuencia correcta es
*sellar → ventilar → calentar*; hacerlo al revés castiga. Esto obliga a leer la sala antes
de apretar.

### Cómo se conectan los sistemas (contrato I/O)

**Escriben en Room3D (fuentes):**

| Fuente | Efecto |
|---|---|
| `CoolantLeak` | `temperature -=` y `contamination +=` proporcional a `leak_intensity` |
| `CoolantTank` vacío | deja de aportar frío → la temperatura se estabiliza (fin de la fuga presurizada) |
| Calefacción / evaporación | `temperature +=` → derrite hielo → `contamination +=` (vapor) |
| Ventilación / `PurgeDial` | `contamination -=` y `pressure -=` |

**Leen de Room3D (consumidores):**

| Consumidor | Variable que lee | Efecto |
|---|---|---|
| `IceLevel` | `temperature < freezing_point` | crecer/decrecer nivel de hielo |
| `CoolantFogAdapter` / `GasArea3D` | `contamination` | densidad de niebla + daño |
| `PressureSection` | `pressure` | ciclo aviso → explosión |
| Daño al jugador | `temperature` / `contamination` | ticks de daño por frío/vapor |

Room3D expone las tres variables como *solo lectura* para los consumidores y una API de
*deltas* para las fuentes (`add_temperature(delta)`, `add_contamination(delta)`,
`add_pressure(delta)`), más señales `temperature_crossed(threshold)`, etc.

## Considered Options

- **A. Estado global de la nave** — una sola presión/temperatura para todo el nivel. Barato
  pero plano: no permite que una sala esté helada y la vecina no, y mata la lectura espacial
  de la amenaza. Descartada.
- **B. Simulación física de fluidos entre salas (propagación)** — el vapor se mueve de sala
  en sala. Rico pero multiplica el alcance y rompe el VS: Sebastián lo descartó
  explícitamente (2026-08-18). Al backlog.
- **C. Room3D por habitación, sin propagación, umbrales discretos** — cada sala posee su
  estado; los sistemas leen/escriben localmente. Legible, determinista, barato.
  **Seleccionada.**

## Files to Modify

- `core_v2/systems/room/Room3D.gd` (nuevo) — estado ambiental + umbrales + señales
- `core_v2/systems/room/Room3D.tscn` (nuevo) — nodo con los `export` de calibración
- `core_v2/systems/cryo/CoolantLeak.gd` (modificar) — escribir deltas en vez de estado aislado
- `core_v2/systems/cryo/CoolantFlowAdapter.gd` (modificar) — exponer fuga → deltas
- `core_v2/systems/ice/IceLevel.gd` (modificar) — crecer según `temperature`
- `core_v2/systems/atmosphere/PressureSection.gd` (modificar) — leer `pressure` del Room3D
- `core_v2/tests/test_room_environment.gd` (nuevo) — umbrales + determinismo
- `core_v2/tests/test_coolant_puzzle_loop.gd` (actualizar) — loop fuga→hielo→vapor→ventilar

**Fuera de alcance:** `CoolantLab.tscn` (calibración de `export` por Sebastián), geometría,
arte, propagación entre salas, reabastecimiento de tanques por cintas/correas (backlog).

## Plan de tareas (propuesta)

| Tarea | Qué | Ejecutor |
|---|---|---|
| T1 | `Room3D` determinista: 3 vars, umbrales, señales, `replay_sync` + snapshot | Jules |
| T2 | Conectar fuentes (fuga, calefacción, ventilación) y consumidores (hielo, niebla, presión) | Jules |
| T3 | Test de umbrales y de replay del loop completo | Jules |
| T4 | Calibración visual de umbrales en `CoolantLab.tscn` | Sebastián (local) |

## Verification

1. Fuga activa ⇒ `temperature` baja y `contamination` sube; cruzar `freezing_point` hace
   crecer el `IceLevel`.
2. Sellar la fuga ⇒ la temperatura deja de bajar; el hielo deja de crecer.
3. Calentar con ductos cerrados ⇒ `contamination` cruza `hazard_threshold` y hay daño.
4. Ventilar (abrir ductos) ⇒ `contamination` y `pressure` bajan; el hielo, ya evaporado,
   no vuelve.
5. Loop completo en una sala ⇒ vuelve a `SALA ESTABLE` y se mantiene (cierre, no se deshace).
6. Determinismo: snapshot a mitad de ciclo, restaurar, mismos ticks ⇒ mismo estado. Sin `randf()`.

## Riesgos y contratos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | Room3D debe estar en `replay_sync` con `get_snapshot`/`restore_snapshot` (3 floats + latches de umbral). Sin esto, hielo/niebla/presión divergen en replay. | T1 bloquea; mismo contrato que FD-255 R1/R3. |
| R2 | Integración por ticks en `_physics_process`, no `_process` (daño independiente de FPS). | Patrón ya aplicado en `FrostEmitter`/`GasArea3D`. |
| R3 | Props que se apagan solos (FD-224): si Room3D depende de un prop en reposo, el ciclo se congela. | Room3D es autónomo; las fuentes piden `_wants_continuous_step()` cuando inyectan. |
| R4 | GLES2: sin nodo `Particles`; niebla/escarcha por `CPUParticles`/`GasParticleManager` (MultiMesh). | Regla de toda la familia (FD-255 R6). |
