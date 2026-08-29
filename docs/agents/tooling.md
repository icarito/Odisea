# Tooling And Validation

Resumen operativo de herramientas. La referencia de reglas sigue siendo `AGENTS.md`.

## Godot

Usar siempre:

```bash
godot3-bin
```

No usar `godot`, porque puede apuntar a Godot 4 y romper sintaxis GDScript 1.x.

## Tests

Suite completa:

```bash
./runtest.sh
./runtest.sh -a ./core_v2/tests/
```

Tests principales:

```bash
./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
./runtest.sh --oys test_salto_vertical
./runtest.sh --stress
```

Leer resultados si el terminal no muestra todo:

```bash
grep -E "(PASSED|FAILED|ERROR|Total|Exit code|SCRIPT ERROR)" ./reports/gdunit_runner.log
```

## Eval headless de GDScript

Usar el wrapper:

```bash
.claude/skills/run-odisea/eval.sh 'print("[t] threads=", OS.has_feature("threads"))'
```

Variables utiles:

- `EVAL_RAW=1`: output completo de Godot.
- `EVAL_TIMEOUT=<s>`: timeout, default 90s.
- `GODOT_BIN`: override del binario, default `godot3-bin`.

Gotchas:

- El inline corre en `_init()`: usar statements (`var`, llamadas). Para `func`, `const` o `enum`, usar modo archivo `-f`.
- Taggear prints con `[t]` para filtrarlos del ruido del engine.
- `instances leaked at exit` en scripts one-shot suele ser harmless.

## Telemetria y runtime debug

ANNA V1 esta deprecado para trabajo nuevo. Usar ANNA V2 via peer HTTP local:

```bash
tools/ensure_peer.sh
curl -s localhost:4999/status | python3 -m json.tool
curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"
curl -s -XPOST localhost:4999/command -d '{"action":"inspect_node","args":{"path":"/root"}}'
curl -s -XPOST localhost:4999/command -d '{"action":"screenshot"}'
```

Arrancar juego propio:

```bash
tools/launch_game.sh --headless --scene res://core_v2/levels/interiors/Dome_Crio.tscn
tools/launch_game.sh --scene <res://...> --pos "x,y,z"
tools/launch_game.sh --stop
```

Regla de debug: `GET /status` primero, luego `POST /command`.

Si el juego esta pausado o su ventana perdio el foco, ANNA V2 deja de emitir latidos
(el ultimo latido llega marcado con `paused` / `focused: false`). El `/status` queda
congelado en esa muestra, pero la conexion sigue viva y los comandos (`inspect_node`,
`/eval`, `screenshot`) siguen funcionando. Las corridas headless no se ven afectadas;
para forzar el stream en una ventana sin foco, exportar `ANNA_V2_ALWAYS_STREAM=1`.

### Seguridad del loop ANNA / VSCode

- Después de cada comando ANNA que inspeccione o modifique el runtime, revisar la
  **Debug Console de VSCode** antes de continuar. Es la fuente de verdad para
  `Node not found`, `SCRIPT ERROR` y errores que el relay HTTP puede ocultar.
- Nunca usar `get_node()` sobre paths o nombres no verificados: primero usar
  `inspect_node`, `get_node_or_null()` o recorrer hijos por índice. Un fallo de
  inspección no debe escribir errores en la consola del juego.
- Limitar las consultas a un comando por vez y respetar `504 timeout`; no hacer
  ráfagas de `/eval` contra un juego ocupado.
- ANNA es observabilidad: un comando fallido debe devolver un error controlado
  sin bloquear ni crashear el motor. Si el bridge compromete el runtime, detener
  los comandos y corregir/aislar el bridge antes de seguir depurando gameplay.

Comandos modificadores como `set_property`, `/eval`, `spawn_scene` y `teleport_player`
requieren debug/editor build. Confirmar con:

```bash
curl -s "localhost:4999/eval?expr=OS.is_debug_build()"
```

## Props

Validar y capturar estados:

```bash
./test_prop.sh <PropName>
./test_prop.sh <PropName> --base64
```

Artefactos:

```text
test_output/props/<PropName>_0_idle.png
test_output/props/<PropName>_1_mid.png
test_output/props/<PropName>_2_active.png
test_output/props/<PropName>_3_off.png
```

Despues de cambios visuales, mostrar capturas al usuario antes de cerrar la iteracion.

## UI retro

```bash
./test_ui.sh --scene=DebugOverlay --base64
./test_ui.sh --scene="res://core_v2/ui/retro/DebugOverlay.tscn"
```

Artefactos en `test_output/ui/`.

## Niveles: Qodot / TrenchBroom

Convenciones y flujo (agregar un prop, una textura, cablear a un circuito, re-exportar
el FGD): `docs/tooling/QODOT_PIPELINE.md`. Estado y auditoria:
`docs/tooling/QODOT_INTEGRATION_AUDIT.md`.

`Qodot.fgd` es GENERADO desde los `.tres`; no editarlo a mano.

```bash
godot3-bin --no-window -s tools/qodot_audit_props.gd      # mide AABB y exports reales
python3 tools/qodot_sync_point_class_sizes.py             # corrige meta_properties.size
godot3-bin --no-window -s tools/qodot_export_fgd.gd       # regenera Qodot.fgd
godot3-bin --no-window -s tools/qodot_validate.gd         # FGD + texturas + qodot_map.gd
godot3-bin --no-window -s tools/qodot_wiring_smoke.gd     # cableado targetname -> target
godot3-bin --no-window -s tools/qodot_build_smoke.gd      # todos los .map generan geometria
python3 tools/check_resource_refs.py                      # ningun ext_resource colgado
godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd  # instala GameConfig.cfg + plantilla en TrenchBroom
```

## Assets e imports

Si se tocan assets, manifests o imports:

```bash
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
scripts/godot_import_smoke.sh --godot-bin godot3-bin --project-path . --clean-cache 0 --import-mode quick
```

No borrar `.import/` como cache: contiene artefactos versionados criticos.
