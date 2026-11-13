# FD-249: CoreV2 Adaptive Tick Rate (Anti-Death-Spiral)

**Status:** In Progress
**Priority:** High
**Effort:** Small
**Branch:** main
**Created:** 2026-08-11
**Completed:** -

## Problem

El CoreV2 usa fixed timestep (`FIXED_DT = 1/60`) en `_physics_process`. En
hardware lento (Android viejito), cada tick de simulación (`player.step()`,
plataformas, CinematicManager, ghost) es pesado. Godot 3 por defecto permite
hasta 8 `physics_steps_per_frame` — si el device no da abasto, los ticks
pendientes se acumulan y cada frame de render ejecuta 4, 6, 8 ticks de simulación:

1. Frame N: 1 tick pesado → 55ms
2. Frame N+1: 3 ticks acumulados → 90ms
3. Frame N+2: 5 ticks acumulados → 150ms → ingame

**Espiral de la muerte**: cuanto más tarda cada tick, más ticks se acumulan,
más tarda el frame → pérdida de control, input lag extremo.

## Solution

Dos cambios orquestados:

### 1. Limitar `max_physics_steps_per_frame`
- `Engine.max_physics_steps_per_frame = 4` (default Godot 3: 8).
- Rompe el ciclo: máximo 4 ticks por frame visual, sin importar cuánto
  tarde el hardware.
- Si los 4 ticks se agotan y aún no alcanzó el tiempo → Godot ralentiza la
  física (siguiente tick en el próximo frame de render).

### 2. Adaptive time scaling (slow-motion controlado)
- Monitorear cuántos ticks se ejecutan por frame de render (leer `Engine.get_physics_frames()` entre frames).
- Si el promedio de ticks/frame supera un umbral (ej. >1.5 en ventana de 60 frames):
  reducir `Engine.time_scale` gradualmente (ej. factor 0.8, luego 0.6).
- Si los ticks/frame bajan (juego se recupera): restaurar `time_scale`
  gradualmente.
- El render se interpola con `delta` del frame visual → el jugador ve
  movimiento fluido aunque la simulación vaya reducida.
- Floor: `time_scale` mínimo 0.3 (30% de velocidad). Por debajo de eso, el
  juego es injugable de todas formas.
- Determinismo: `time_scale` afecta `step_dt = FIXED_DT * Engine.time_scale`
  en todas las entidades uniformemente → misma cantidad de ticks
  deterministas.

### Considered Options
- **Option A: solo cap** — simple, rompe la espiral pero el juego puede
  sentirse "a trompicones" en hardware límite.
- **Option B: cap + adaptive scale (selected)** — smooth, el jugador siente
  que "el mundo se ralentiza" en vez de "el juego se parte". Misma
  complejidad que Option A con ~30 líneas extra.
- **Option C: dynamic FIXED_DT** — cambiar el timestep rompe determinismo
  (distinto número de ticks → distinto resultado). Rechazado.

## Files to Modify

- `project.godot` — `physics/common/physics_fps = 60`, agregar
  `physics/common/max_physics_steps_per_frame=4` si no existe.
- `core_v2/autoloads/SessionManager.gd` — agregar monitor de ticks/frame
  (sección de `_process` o `_physics_process`), lógica de adaptive scale.
- Opcional: exponer configuración en `OYS_Settings` o settings UI.

## Measurement

Jules debe medir antes y después:

1. Instalar contador: `ticks_per_render_frame` promedio + p99 en loop de
   gameplay con carga simulada (muchas plataformas, IA activa).
2. Simular device lento: agregar `OS.delay_msec(N)` artificial en
   `PlayerControllerV2.step()` para emular hardware débil — medir cuántos
   ticks/frame se acumulan con y sin el adaptive cap.
3. Telemetría: reportar `perf.physics_ticks_per_frame` en ghosts (extender
   ANNAV2 si se necesita) para medir en producción real.
4. Reporte comparativo de input lag percibido (subjetivo) y ticks/frame
   (objetivo) con la configuración nueva.

## Determinism Contract

- `Engine.time_scale` se aplica uniformemente → mismo número de llamadas a
  `step()` para la misma secuencia de inputs.
- `test_determinism_v2.gd` debe pasar con adaptive scale activo y sin él.
- Replays grabados con time_scale≠1.0 deben reproducirse idénticos.

## Verification

1. `test_determinism_v2.gd` — pasar con cap + adaptive scale.
2. Prueba manual: gameplay en escena pesada (Dome_Crio con IA + ghost),
   verificar que no se acumulan >4 ticks/frame.
3. Ghost telemetry: antes/después de `perf.physics_ticks_per_frame` en
   device Android viejo.
4. Benchmark: `tools/bench_tick_adaptive.gd` — genera carga artificial,
   reporta ticks/frame y time_scale resultante.
