---
description: Evaluar GDScript headless sin lanzar el juego completo (eval.sh wrapper)
---

# /odisea-eval — Evaluar GDScript headless

Fuente canonica compartida: `docs/agents/tooling.md`.

Ejecuta GDScript dentro de un `SceneTree` real sin ventana (audio muteado). Es la forma más rápida de ejercitar sistemas internos (generadores, rotators, parsers) sin bootear el juego completo.

## Uso

```bash
# Inline — corre dentro de SceneTree._init(), quit() automático
.claude/skills/run-odisea/eval.sh 'print("[t] threads=", OS.has_feature("threads"))'

# Multi-línea, importa y llama código interno
.claude/skills/run-odisea/eval.sh 'var m=load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
m.apply_params({"grid_width":8,"grid_depth":12})
print("[t] MST cells=", m.generate_grid_data(7).size())'

# Cargar escena para confirmar que instancea
.claude/skills/run-odisea/eval.sh 'var inst=load("res://core_v2/levels/interiors/Dome_Crio.tscn").instance()
print("[t] Dome_Crio children=", inst.get_child_count())'

# Modo archivo (script que `extends SceneTree`)
.claude/skills/run-odisea/eval.sh -f /tmp/my_check.gd
```

## Variables de entorno

- `EVAL_RAW=1` — muestra output sin filtrar de Godot
- `EVAL_TIMEOUT=<s>` — timeout (default 90s)
- `GODOT_BIN` — override del binario (default `godot3-bin`)

## Syntax-check rápido (sin eval.sh)

```bash
godot3-bin --no-window --check-only -s core_v2/systems/WorldRotator.gd 2>&1 | grep -i "parse error"
```

## Gotchas

- El inline body corre en `_init()`: solo statements (`var`, no `const`/`enum`/`func`). Para esos usar `-f script.gd`.
- Taggear prints con `[t]` para filtrar del ruido del engine.
- `--check-only` contra scripts que usan autoloads imprime errores de "isn't declared" — es el autoload no cargado en aislamiento, no un error real.
- `instances leaked at exit` es harmless en scripts one-shot.
