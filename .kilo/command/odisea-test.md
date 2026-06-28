---
description: Ejecutar tests del proyecto: GdUnit3, OYS determinismo, stress, prop validation, UI validation
---

# /odisea-test — Ejecutar tests

Fuente canonica compartida: `docs/agents/tooling.md`.

## Suite completa

```bash
./runtest.sh                          # recomendado (paralelo)
./runtest.sh -a ./core_v2/tests/      # equivalente explícito
```

## Tests selectivos

```bash
./runtest.sh -a ./core_v2/tests/test_mi_feature.gd    # GdUnit3
./runtest.sh --oys test_salto_vertical                 # OYS (determinismo)
./runtest.sh --stress                                  # Stress test suite
```

## Tests principales

```bash
./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd     # Modos de gravedad y zero-g
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd    # Determinismo del Core
```

## Validación de Props

```bash
./test_prop.sh <PropName>              # Captura screenshots de estados del prop
./test_prop.sh <PropName> --base64    # PNG en stdout (para inspección del agente)
```

Screenshots en `test_output/props/<PropName>_0_idle.png`, `_1_mid.png`, `_2_active.png`, `_3_off.png`.

## Validación de UI

```bash
./test_ui.sh --scene=DebugOverlay --base64
./test_ui.sh --scene="res://core_v2/ui/retro/DebugOverlay.tscn"
```

Screenshots en `test_output/ui/<scene_name>_*.png`.

## Leer output de tests

El output se guarda en `./reports/gdunit_runner.log`:

```bash
grep -E "(PASSED|FAILED|ERROR|Total|Exit code|SCRIPT ERROR)" ./reports/gdunit_runner.log
```

## Evaluación headless de GDScript

```bash
.claude/skills/run-odisea/eval.sh 'print("[t] threads=", OS.has_feature("threads"))'
.claude/skills/run-odisea/eval.sh 'var m=load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
m.apply_params({"grid_width":8,"grid_depth":12})
print("[t] MST cells=", m.generate_grid_data(7).size())'
```

## Gotchas

- **Godot binario**: usar siempre `godot3-bin` (Godot 3.6), no `godot` (puede ser v4).
- **OYS tests**: corren record + replay (~80s cada uno). Son determinísticos.
- **Delta assertions en props**: el warning de delta <2% es esperado en props sin animación. El exit code es la autoridad.
- **`ERROR: NO GRAB`**: harmless en headless. Los tests pasan igual.
- **`--runner` flag**: NO es válido para GdUnit3. `runtest.sh --oys` no acepta `--runner`.
