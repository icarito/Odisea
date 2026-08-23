# Fallos preexistentes de los tests de determinismo

> Diagnóstico levantado el 2026-06-21 al arreglar el timeout diario del workflow
> `Determinism Tests` (GH Actions). **El timeout de CI ya está resuelto** (ver más
> abajo); este documento cataloga los fallos de **drift/assert** que son
> independientes y preexistentes, para investigarlos por separado.

## Contexto: el fix del timeout de CI (ya aplicado)

El job se cancelaba a diario al llegar a `timeout-minutes: 25`. **No era un cuelgue**:
en headless, el render por software de las escenas 3D pesadas baja el framerate a
~1 FPS, así que cada test pasaba de segundos a >60s y la suite entera no terminaba.

Fix (en `core_v2/tests/test_determinism_v2.gd` + `runtest.sh`):
- `runtest.sh` exporta `OYS_RENDER_DISABLED=1` cuando lanza sin ventana (`--no-window`).
- El harness desactiva `render_target_update_mode` (`UPDATE_DISABLED`) por test, salvo
  que el `.oys` declare la directiva `OYS_REQUIRE_RENDER` (tests que dependen de
  render/shader: `test_sgc_orbit`, `test_cargol_basic`).
- `--show` / `OYS_FORCE_RENDER=1` conservan el render para depuración visual.

Efecto medido: `test_pro` 36s → 0.7s; la mayoría de los tests headless bajan a <10s.

## Fallos de drift/assert (a investigar aparte)

Medidos en headless con el fix aplicado. **Ninguno fue causado por esta sesión**;
re-grabar los snapshots produce archivos byte-idénticos a los commiteados, así que
los `.json` NO están obsoletos — el problema es de comportamiento / datos de baseline.

### Bucket B — `final_expected_state` quedó en el origen (baseline nunca grabado bien)

Estos `.json` tienen `expected ≈ (0, *, 0)` (posición inicial), por lo que cualquier
movimiento real dispara drift enorme. El snapshot de baseline nunca se grabó con un
estado final válido.

| Test | expected (stale) | drift |
|------|------------------|-------|
| `test_salto_vertical` | `(0, 0.0415, 0)` | 1.00 |
| `test_killzone_signal` | `(0, 0.0415, 0)` | 21.8 |
| `reproduction_blend` | `(0, -0.3585, -3)` | 1.00 |
| `test_tube_airlock` | `(0, 0.425, -17)` | 17.3 (+ OYS ASSERT) |

**Acción sugerida:** regrabar el baseline con `--snapshot` una vez confirmado que el
comportamiento actual del OYS es el correcto, y commitear el `.json` resultante.

### Bucket C — drift real de comportamiento

| Test | drift | nota |
|------|-------|------|
| `test_locomocion_walk` | 0.010001 | marginal: replay diverge ~1 step del recording |
| `test_locomocion_adelante` | 0.0125 | marginal |
| `test_locomocion_atras` | 0.058 | moderado |
| `test_locomocion_strafe` | 2.28 | grande (tank-turn cambió el strafe) |
| `test_salto_desplazamiento` | 0.045 | moderado |
| `test_sidescroll_acrobatic` | 2.04 | grande |
| `test_cargol_starter` | — | revisar |
| `test_push_clipping` | 5.99 | grande |
| `test_reverse_tank` | — | revisar |
| `test_dome_crio_airlock_*` | 17–36 | transición/teleport: baseline desfasado |

Los marginales de locomoción (`walk` 0.010001 justo sobre el umbral 0.01) sugieren un
off-by-one-step entre la grabación del OYS (`final_expected_state`) y el replay desde
buffer: el replay corre un paso de física extra. Vale revisar el cierre del buffer en
`SessionManager.play_buffer` / el frame en que se captura `final_expected_state`.

### Tests lentos/flaky en headless (timeout aun con render)

`test_destroyer_debug`, `run_test_zg`, `test_ghost_trigger_loop` hacen timeout en
headless incluso con render activo (sólo pasaban con display real). Tratar como
flaky de headless, no como regresión del fix de render.
