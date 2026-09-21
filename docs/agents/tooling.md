# Tooling And Validation

Resumen operativo de herramientas. La referencia de reglas sigue siendo `AGENTS.md`.

## Godot

Usar siempre el fork con Box3D:

```bash
tools/godot            # wrapper: ejecuta lo que resuelve tools/godot_bin.sh
```

`tools/godot_bin.sh` imprime la ruta del editor construido del fork (y lo reconstruye
si el fork cambio). Nunca `godot3-bin`: es el 3.6.2 stock, sin Box3D (cae a Bullet en
silencio), no exporta Android y borra settings de `project.godot`. Tampoco `godot`, que
puede ser Godot 4. VSCode (`godotTools.editorPath.godot3`), el `GODOT` del Makefile y el
hook pre-push ya apuntan a `tools/godot`.

## Tests

En desarrollo local, ejecutar solamente los tests puntuales afectados; la suite completa corresponde a CI. Usar pytest headless por defecto para GdUnit/OYS y Python, seleccionando el nodo o archivo afectado:

```bash
./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_gravity_modes_gd
./.venv/bin/pytest tests/test_modulo.py
```

Descubrir el nodo de un test GdUnit/OYS antes de correrlo:

```bash
./.venv/bin/pytest tests/test_odisea_runner.py --collect-only -q -k test_gravity_modes
./runtest.sh --list          # suites GdUnit, casos OYS y como descubrir nodos pytest
```

`runtest.sh` sigue disponible para invocaciones directas o cuando se necesite su salida específica.

### Backend de tests: Server headless, igual que CI (contrato)

`runtest.sh` selecciona **siempre el binario `platform=server` del release pinneado del fork**
y lo corre con `--headless --no-window`, aunque la máquina tenga `DISPLAY`. Pasar esas flags
al editor X11 de Godot 3 no cambia su backend. CI usa el Server pinneado: un run local con
X11 oculto (`--no-window` solo) **no valida CI**, porque cambia el driver de ventana/input y
el mouse virtual y Box3D pueden dar resultados distintos (asserts que pasan local y fallan
en CI, o al revés). `--show` es la única vía gráfica y sirve para mirar, no para validar.
`tests/test_runtest_runner_contract.py` (corre en CI) detecta una reintroducción de la
bifurcación por display.

Paridad con CI, todo overrideable por env:

- `ANNA_V2_NO_CENTRAL=1` y `ODISEA_TEST_TIMEOUT_SEC=180` son el default local (igual que CI).
- `--ci` reproduce el job core tal cual: gdunit en **8 shards secuenciales** (procesos Godot
  frescos, suites en orden alfabetico = membresia determinista), sin determinismo, preflight
  ya hecho y `timeout` de pared de 540s. Usarlo para reproducir un fallo de CI; el default
  local (delegate pytest, un Godot por suite) cambia el orden y la orfandad acumulada.
- `ODISEA_RETRY_ISOLATED=1` (solo lo fija el job de CI): si el run sharded termina con fallos
  de tests, cada suite fallida se re-corre **aislada** en un proceso fresco. Si pasa aislada
  el gate sale verde con un `::warning` visible (flake de corrida larga); si sigue fallando,
  es un bug real y el gate queda rojo. `--ci` NO lo activa: reproduce fallos, no los rescata.
- `--filter <substring>` corre nodos pytest puntuales (fuerza el delegate) y `--list` lista
  los targets disponibles.

Por qué shards: el proceso único de gdunit envejecía el SceneTree (orphans acumulados,
estado de autoloads) y las suites físico-sensibles de fin de corrida
(`test_ringhub_wakeup` corría en posición ~148/150) flakeaban **con el mismo commit**
(fallos distintos por intento, verde al reintentar). Cada shard arranca con árbol fresco,
así que la contaminación solo puede venir de las ~19 suites del propio shard.
`tests/test_runtest_runner_contract.py` blinda cobertura exacta (`--shards`), rescate
y backend en CI.

```bash
./runtest.sh --ci                         # reproducción fiel del job core de CI (8 shards)
./runtest.sh --shards 4 -a ./core_v2/tests/   # sharding manual (solo runner gdunit)
./runtest.sh --filter cryopod             # nodos pytest que matcheen
./runtest.sh --print-command -a <suite>   # comando headless resuelto, sin ejecutar Godot
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
- `GODOT_BIN`: override del binario, default `tools/godot_bin.sh` (fork con Box3D).

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

## Push de escenas ad hoc a un juego corriendo (device)

Empaquetar una escena local, subirla e inyectarla en el juego vivo (Anbernic o cualquier
device con peer local) sin re-exportar. La puesta a punto del device es un solo comando
(idempotente: instala el engine debug del release del fork, arranca el peer, escribe
`dev.sh` con el bridge y reinicia si hace falta):

```bash
export PORTMASTER_HOST=root@192.168.18.36          # opcional; default root@angel.local
tools/push_scene_pck.sh --setup                    # deja el RG351V listo para comandos ANNAV2
tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn --no-launch
curl -s --get --data-urlencode \
  "expr=get_node('/root/SceneManager').goto_scene('res://core_v2/levels/RingHub_Level.tscn')" \
  "$ANNA_PEER_URL/eval"                            # entrar con el flujo de spawn normal
tools/push_scene_pck.sh --restore                  # volver al arranque normal del port
```

Extras (archivos `res://` que NO están en el pack principal, ej. un environment nuevo):

```bash
tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn \
  res://scenes/common/space_environment/Environment_RingHub.tres --id mi_test
```

Para **iterar la misma escena en caliente** usar `--unique`: expone la escena bajo
`res://.dev_push/<id>.tscn` y hay que entrar a esa ruta (Godot cachea por path, así que
re-subir la misma `res://` mostraría la versión vieja hasta reiniciar).

```bash
tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn --no-launch --unique
```

Documentación completa (requisitos del device, gotchas de spawn/escena, medición en serie):
`.agents/skills/run-odisea/SKILL.md`, sección "Push an ad hoc scene to a running game".

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
tools/godot --no-window -s tools/qodot_audit_props.gd      # mide AABB y exports reales
python3 tools/qodot_sync_point_class_sizes.py             # corrige meta_properties.size
tools/godot --no-window -s tools/qodot_export_fgd.gd       # regenera Qodot.fgd
tools/godot --no-window -s tools/qodot_validate.gd         # FGD + texturas + qodot_map.gd
tools/godot --no-window -s tools/qodot_wiring_smoke.gd     # cableado targetname -> target
tools/godot --no-window -s tools/qodot_build_smoke.gd      # todos los .map generan geometria
python3 tools/check_resource_refs.py                      # ningun ext_resource colgado
tools/godot --no-window -s tools/qodot_export_trenchbroom_config.gd  # instala GameConfig.cfg + plantilla en TrenchBroom
```

## Assets e imports

Si se tocan assets, manifests o imports:

```bash
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
scripts/godot_import_smoke.sh --godot-bin tools/godot --project-path . --clean-cache 0 --import-mode quick
```

No borrar `.import/` como cache: contiene artefactos versionados criticos.
