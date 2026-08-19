# FD-270 T3 (J3): Autoridad del parche — de manómetro a caudal

## Objetivo

`LeakPatchPoint.patch_with_gloo()` deja de leer el manómetro para decidir si un parche es firme o
provisorio, y pasa a preguntarle al `CoolantFlowAdapter` si el tramo de la fisura tiene caudal.

## Contexto del sistema

Godot 3.6 / GDScript 1.x (`export()` con paréntesis, `yield` nunca `await`). Todo en `core_v2/`.

Archivo a editar: `core_v2/systems/cryo/LeakPatchPoint.gd` (leelo completo antes de tocar nada,
ya está en el repo).

Estado actual (el bug que arreglás): `patch_with_gloo()` lee `_manometer.get_pressure()` si hay
manómetro conectado, si no cae a un fallback (`leak_intensity > 0.01 => pressure = 1.0`). El
manómetro se está retirando del puzle en este FD (decisión ya tomada), así que hay que mover la
autoridad **antes** de que se vaya, o el sistema cae al fallback en silencio y deja de funcionar
bien.

## Dependencia: contrato de `CoolantFlowAdapter` v2 (en curso, ver abajo)

Hay otra tarea en paralelo (T2/J2) reescribiendo `core_v2/systems/cryo/CoolantFlowAdapter.gd`.
Cuando tu tarea empiece, es posible que esa reescritura todavía no esté en el repo o esté a medio
terminar — **no la esperes ni la edites**, escribí tu código contra el contrato que sigue, que es
lo que la otra tarea va a entregar:

```gdscript
# En CoolantFlowAdapter (ya existe o va a existir con este nombre):
func is_pressurized_at(node: Node) -> bool
```

`is_pressurized_at(node)` recibe un nodo (una fisura, típicamente `_leak` de `LeakPatchPoint`) y
devuelve `true` si el tramo de tubería donde está esa fisura tiene caudal `> 0.0`, `false` si está
seco (sin caudal, o sea "despresurizado", listo para parche firme).

`LeakPatchPoint` ya tiene un campo `flow_adapter_path: NodePath` (exportado, ya existe en el
archivo actual — mirá `_resolve_references()`) que resuelve a `_flow_adapter`. Ese es el objeto al
que le llamás `is_pressurized_at()`.

## Cambio exacto

En `patch_with_gloo()`, reemplazá todo el bloque que arma `pressure` y calcula
`applies_firmly` leyendo el manómetro:

```gdscript
# ANTES (a borrar):
var pressure := 0.0
if _manometer != null and _manometer.has_method("get_pressure"):
    pressure = float(_manometer.get_pressure())
elif _leak != null and _leak.has_method("get_leak_intensity"):
    var leak_intensity: float = float(_leak.get_leak_intensity())
    if leak_intensity > 0.01:
        pressure = 1.0
var applies_firmly := (pressure <= firm_patch_pressure_threshold)
```

Por:

```gdscript
# DESPUÉS:
var is_pressurized := true
if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at") and _leak != null:
    is_pressurized = bool(_flow_adapter.call("is_pressurized_at", _leak))
var applies_firmly := not is_pressurized
```

Notá que esto **cambia la semántica de `firm_patch_pressure_threshold`**: antes era un umbral
sobre una presión continua (`pressure <= threshold`), ahora `is_pressurized_at` devuelve un
booleano — el umbral deja de tener sentido para esta decisión. **Dejá el export
`firm_patch_pressure_threshold` en el archivo** (no lo borres, otro código o escena podría
referenciarlo, y borrar un export rompe cualquier `.tscn` que lo tenga seteado), pero dejá de
usarlo en el cálculo de `applies_firmly` como se ve arriba. Si el linter/type-checker se queja de
una var sin uso, un comentario de una línea alcanza para explicar que quedó de la era del
manómetro y ya no gobierna la decisión.

`_manometer` y `manometer_path` (el export y la resolución en `_resolve_references()`) — **dejalos
como están**, no los borres en esta tarea. Sacar el manómetro de la escena es una tarea de escena
aparte (no tuya). Vos solo dejás de *usar* `_manometer` para la decisión de parche firme.

## Archivos permitidos

- `core_v2/systems/cryo/LeakPatchPoint.gd`
- Un test GdUnit3 nuevo en `core_v2/tests/` (ver criterio de aceptación abajo)

## Archivos prohibidos

- `core_v2/systems/cryo/CoolantFlowAdapter.gd` (otra tarea la está escribiendo en paralelo)
- `core_v2/systems/pipe/PipeNetworkResource.gd`
- `core_v2/systems/cryo/CoolantLeak.gd`
- Cualquier `.tscn`, `project.godot`

## Criterio de aceptación

Test GdUnit3 `test_firm_patch_requires_zero_flow` (o el nombre que uses, que cubra el mismo caso):

- Con un adapter mock/stub que responde `is_pressurized_at() -> true`: parchear con
  `patch_with_gloo()` debe dar un parche **provisorio** (`is_firmly_patched() == false`).
- Con un adapter mock/stub que responde `is_pressurized_at() -> false`: parchear debe dar un
  parche **firme** (`is_firmly_patched() == true`).

Para el mock, no hace falta instanciar `CoolantFlowAdapter` real — un `Node` con
`set_script()` de un script mínimo que expone `is_pressurized_at(node) -> bool` alcanza, o un
`Node.new()` con `add_user_signal`/método dinámico si preferís. Mirá
`core_v2/tests/test_pipe_network_resource.gd` (ya en el repo) para el estilo general de test:
`extends GdUnitTestSuite`, `auto_free()`, `assert_*`.

Correr `./runtest.sh -a core_v2/tests/<tu_test>.gd` y que pase.

## Qué NO hacer

- No edites `CoolantFlowAdapter.gd` — otra tarea lo está escribiendo, tocarlo genera conflicto de
  merge.
- No borres `_manometer`, `manometer_path`, ni `firm_patch_pressure_threshold` del archivo.
- No cambies la lógica de `_unpatch()`, `remove_patch()`, `seal()` ni ninguna otra función de
  `LeakPatchPoint.gd` — el cambio es acotado a cómo se calcula `applies_firmly` dentro de
  `patch_with_gloo()`.
- No toques ninguna escena.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
