# FD-216: Fix Determinism Tests Timeout — Paralelizar + Aumentar Límite

**Status:** Open
**Priority:** High
**Effort:** Small
**Created:** 2026-06-15
**Completed:** -

## Problem

El workflow `Determinism Tests` corre secuencialmente 34 tests .oys con `timeout 60` cada uno (~60s máx cada test) + overhead de setup/imports ≈ ~25-28 min total. El workflow tiene `timeout-minutes: 25`, por lo que TODAS las ejecuciones se cancelan por timeout desde hace al menos 12 días. Esto hace que el test de determinismo nunca se ejecute realmente y no dé señales de regresión.

## Solution

Dos cambios:

### 1. Subir timeout-minutes a 45

En `.github/workflows/determinism_tests.yml`, cambiar `timeout-minutes: 25` → `timeout-minutes: 45` para que los tests tengan margen de completar sin cancelarse.

### 2. Paralelizar tests en 2 jobs

Dividir los 34 .oys en 2 grupos balanceados por tiempo estimado:
- **Grupo A (locomoción + airlock + pesados)**: ~18 tests, ~15 min
- **Grupo B (cargol + scaffold + misc)**: ~16 tests, ~10 min

Cada grupo corre como un job independiente con su propio `timeout-minutes: 25`. Esto reduce el tiempo real a la mitad y da margen para añadir más tests sin romper el límite.

División propuesta:

```
Grupo A (locomotion + airlock + pesados):
  test_locomocion_adelante.oys
  test_locomocion_atras.oys
  test_locomocion_strafe.oys
  test_locomocion_walk.oys
  test_salto_vertical.oys
  test_salto_desplazamiento.oys
  test_camara_rotacion.oys
  test_dome_crio_airlock_multi_cycle.oys
  test_dome_crio_airlock_regret_pre60.oys
  test_dome_crio_airlock_return.oys
  test_dome_crio_airlock_transition.oys
  test_push_clipping.oys
  test_push_integration.oys
  test_tube_airlock.oys
  test_killzone_signal.oys
  test_reverse_tank.oys
  test_sidescroll_acrobatic.oys
  test_sgc_orbit.oys

Grupo B (cargol + scaffold + misc + perf + pro):
  test_cargol_basic.oys
  test_cargol_starter.oys
  test_cinematic_input_latch.oys
  test_destroyer_debug.oys
  test_ghost_trigger_loop.oys
  test_oys_trigger.oys
  test_pro.oys
  test_scaffold_wfc.oys
  test_zero_g_roll_ots_camera.oys
  test_anna_scene_visual.oys
  test_anna_v2_telemetry.oys
  debug_perf.oys
  perf_ab_test.oys
  perf_test.oys
  reproduction_blend.oys
  run_test_zg.oys
```

### 3. Mejora: timeout por test con reporting

En el script del workflow, cambiar `timeout 60` → `timeout 120` para dar margen a tests lentos (airlock multi-cycle) sin que un solo test que se cuelga mate el job entero. El timeout de 120 es absorbido por el límite del job.

## Files to Modify

1. `.github/workflows/determinism_tests.yml` — duplicar job, dividir tests en 2 matrices, ajustar timeouts

## Verification

1. Workflow corre los dos jobs en paralelo en CI
2. Cada job completa dentro de 25 min
3. El workflow completo completa dentro de 30 min total
4. Tests individuales pasan o fallan con output en el summary
5. Si un test se cuelga, su job timeout a los 25 min pero el otro job sigue e informa resultados parciales
