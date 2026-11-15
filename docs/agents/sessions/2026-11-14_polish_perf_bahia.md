# 2026-11-14 — Pulido de perf: streaming por estación en la Bahía de máquinas

Rama: `ao/pulido-del-vertical-2/root` · commit: `perf(machine-bay): stream stations by proximity behind generic activator`
Base: `origin/main` @ `e3546c1c` (rebase limpio).

## Síntoma y objetivo

`core_v2/levels/machines/MachineBay.tscn` + `machine_bay.json` construían **toda** la
bahía al cargar (`MachineLevel.load_layout_file` → `build`): las 4 máquinas + la válvula
maestra quedaban activas y visibles a la vez. Objetivo: dejar construidas todas las
estaciones pero **activar solo la del jugador (± vecina)** por cercanía, con una clave
de agrupación **genérica por `station`/área** (no atada a las 4 máquinas actuales),
aprovechable por la bahía vertical de src-53.

## Qué se hizo

- **Nuevo activador reusable** `core_v2/levels/chunks/ProximityNodeActivatorV2.gd`:
  activador de cercanía **en el lugar** (no instancia/libera escenas, a diferencia de
  `StreamedSceneChunkV2`). Registra "chunks" = `{nodes, center, radius, margin}` y
  apaga/enciende `visible`, colisión y `process`/`physics_process` del subárbol; los
  `RigidBody` quedan en `MODE_STATIC` dormidos. Al reactivar restaura el estado guardado.
  Si un nodo expone `set_stream_active(active)` se encarga él (así `MachinePart` respeta
  su estado de corte). Reusable por cualquier nivel por áreas (src-53).
- **Gancho mínimo en `MachineLevel.gd`** (opt-in, ~70 líneas, sin reestructurar `build`):
  `export bool enable_station_streaming := false`, `export float station_stream_margin := 14.0`,
  `get_station_ids()`, `_setup_station_streaming()`, `set_station_streaming_enabled()`,
  `get_station_streamer()`. Un chunk por `station > 0`; la `station 0` (shell/ambiente)
  queda siempre activa. Centro/radio salen del AABB de los ítems de la estación (en
  coordenadas **globales**, que es contra lo que compara el activador).
- **`MachinePart.set_stream_active()`**: respeta `_is_cut`/`held` al reactivar (una
  estación apagada y encendida conserva su partida). Además registra `_stream_active`:
  un `release()`/`set_active()` tardío (link con retardo) sobre una pieza fuera de área
  cambia solo el estado lógico y **no** la despierta; al volver, la estación la pone en
  `MODE_RIGID`. `_apply_cut_state()` también respeta `_stream_active` (no la hace visible
  si el rearme llega con la estación apagada).
- **Producción**: `MachineBay.tscn` trae `enable_station_streaming = true` en el nodo
  `Level`. El default del export sigue en `false` para no alterar tests/layout.
- **Tests**:
  - `core_v2/tests/test_machine_station_streaming.gd` (headless, sin render): 1 chunk por
    estación (>0), toggle por distancia, `station 0` nunca se apaga, corte sobrevive al ciclo.
  - `core_v2/tests/test_machine_bay_perf.gd` (probe de medición): imprime la tabla por
    pose. En headless el rasterizer dummy devuelve 0 y no aporta (pero no falla).

## Metodología de medición

- `VisualServer.force_draw()` + `INFO_DRAW_CALLS_IN_FRAME` / `INFO_OBJECTS_IN_FRAME` /
  `INFO_VERTICES_IN_FRAME`, como `test_ringhub_occlusion_render.gd`. **En headless el
  rasterizer dummy devuelve 0**: hay que medir con `--show`.
- Poses fijas (mismo punto de vista por estación, cámara mirando +Z). Se descarta el
  warm-up (12 ticks) antes de muestrear 6 ticks. Nunca A/B de FPS: se comparan métricas
  de render por pose.
- Comando:
  ```shell
  STREAMING=0 ./runtest.sh --show -a ./core_v2/tests/test_machine_bay_perf.gd   # antes
  STREAMING=1 ./runtest.sh --show -a ./core_v2/tests/test_machine_bay_perf.gd   # después
  # la tabla queda en reports/gdunit_*.log, líneas [MEASURE]
  ```
- A/B/A: el control (STREAMING=0) reproduce el comportamiento actual; los valores
  "después" son estables entre corridas (±0).

## Tabla antes / después (misma escena, mismas poses)

Draw calls / objetos / vértices (promedio de 6 ticks tras warm-up). `physics_ms_max` es
un pico puntual y ruidoso (se dispara por instanciación/spikes del solver): no se usa
para A/B, se deja solo como referencia.

| pose     | draws antes | draws después | Δ draws | objetos antes→después | vértices antes→después |
|----------|------------:|--------------:|--------:|----------------------:|-----------------------:|
| spawn    | 4553 | 3943 | **-610 (-13.4%)** | 777 → 669 | 1 618 783 → 1 421 860 |
| station1 | 4358 | 3739 | **-619 (-14.2%)** | 701 → 593 | 1 553 484 → 1 354 437 |
| station2 | 1786 | 1082 | **-704 (-39.4%)** | 333 → 225 | 540 810 → 318 723 |
| station3 | 1218 |  978 | **-240 (-19.7%)** | 216 → 188 | 442 865 → 350 702 |
| station4 |  913 |  913 |   0 | 191 → 191 | 361 878 → 361 878 |
| station5 |  738 |  738 |   0 | 150 → 150 | 348 477 → 348 477 |
| exit     |  256 |  256 |   0 |  17 → 17 | 140 196 → 140 196 |

Interpretación:

- El ahorro aparece donde las estaciones **están dentro del frustum**: spawn y station1
  miran hacia +Z y ven varias estaciones por delante.
- `station4`/`station5`/`exit` no cambian: ya miran hacia el fondo con pocas estaciones
  en view (station5 tiene 3 ítems) y el frustum/fog ya descartaba lo de atrás.
- **El techo actual de draw calls es la `station 0` (shell)**, que sigue siempre activa:
  `BayShellFallback` (muros + ~11 costillas × 3 cajas + tiras) + catwalks + pipes +
  carteles + `BayFireVisual` (partículas). Los 4553 draws del spawn son mayormente shell,
  no máquinas. Por eso el streaming de estaciones topa en ~13-14% ahí.
- El `bay_shell.glb` no existe en el checkout → se usa el fallback procedural. Cuando el
  asset real entre, revisar el costo del shell.

## Estado / pendientes

- [x] Activador genérico por chunk + gancho en MachineLevel + **encendido en la escena
  de producción** (`MachineBay.tscn`), con test sobre la escena real.
- [x] Tabla antes/después.
- [x] Fix de review: `release()`/link tardío fuera de área no despierta la pieza.
- [x] Tests puntuales verdes: `pytest tests/test_odisea_runner.py -q -k
  'test_machine_level or test_machine_bay or test_machine_launch or test_machine_sign_scale'`
  → **11 passed** (incluye `test_machine_station_streaming` y `test_machine_bay_perf`).
- [x] **Cambio seamless en `return_to_ring_hub`** (spec de src-54
  `.operator-shared/specs/seamless-transitions.md` §7), aplicado tras el merge de #412
  (`8a790d1d`): `airlock_manager.notify_transition(target_scene)` + `params["transition"]
  = "seamless"`, conservando `ringhub_return_state` y `state_data.player_snapshot`.
  `test_machine_bay_return.gd` actualizado al nuevo contrato (sin `wait_for_fade_out`) y
  con snapshot/restore del estado de `AirlockManager` para no filtrar entre tests.
- [ ] Siguiente palanca de perf (fuera de este scope): **shell/`station 0`**. La sombra
  direccional duplica draw calls; los 4553 del spawn no se explican por las máquinas.
  Medir apagar sombras / batch del shell antes de tocar más streaming.
- [ ] `station_stream_margin` = 14 m activa la estación ± vecina. Si src-53/la bahía
  vertical necesita otra política, el margen/radio son por llamador (export y parámetros
  de `register_nodes`), sin tocar el activador.

## Cómo retomar

1. `git checkout ao/pulido-del-vertical-2/root` (rebasada sobre `origin/main`).
2. Tests de streaming: `./runtest.sh -a ./core_v2/tests/test_machine_station_streaming.gd`.
3. Medición: los dos comandos `STREAMING=0/1 ./runtest.sh --show -a
   ./core_v2/tests/test_machine_bay_perf.gd` (requiere display; no corre en headless CI).
4. Transición seamless bahía→hub: ya aplicada (§7). Test: `./runtest.sh -a
   ./core_v2/tests/test_machine_bay_return.gd`.
