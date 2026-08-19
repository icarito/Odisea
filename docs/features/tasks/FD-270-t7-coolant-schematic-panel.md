# FD-270 T7 (JM3): `CoolantSchematicPanel` — diagrama esquemático del circuito

## Objetivo

Crear `core_v2/things/CoolantSchematicPanel.gd`: un `Control` que dibuja un diagrama esquemático
simple (líneas + puntos, estilo diagrama de tuberías) mostrando el estado en vivo de las válvulas
y fisuras del sistema de refrigerante, coloreado según su estado.

## Contexto del sistema

Motor Godot 3.6 / GDScript 1.x (`extends`/`class_name`, `export()` con paréntesis, `yield` nunca
`await`). Este panel va a vivir dentro del `Viewport` de un terminal holográfico en pantalla (no lo
edites, es trabajo nuestro instanciarlo ahí) — es solo lectura y dibujo, sin input.

Ya existe `core_v2/things/CoolantSystemStatusUI.gd` (**no lo edites, solo mirá cómo lee el
estado** — es la referencia de qué grupos consultar y qué señales/métodos existen en los nodos):

- Válvulas: `get_tree().get_nodes_in_group("coolant_valve")`. Cada válvula expone la señal
  `valve_state_changed(is_open: bool)` y la propiedad `is_active: bool` (abierta = `true`).
- Fisuras: `get_tree().get_nodes_in_group("gloo_patchable")` son los `LeakPatchPoint` (el punto que
  el jugador parchea). Cada uno expone `is_patched() -> bool` y `is_firmly_patched() -> bool`
  (métodos). Podés leer la fuga asociada con `patch_point.get("_leak")` si el patch point tiene esa
  propiedad interna (mirá `CoolantSystemStatusUI._update_fissure_displays()` para el patrón exacto
  de cómo se accede — replicá esa lectura, no inventes una nueva).
- El estado de una fuga (`CoolantLeak`, `core_v2/systems/cryo/CoolantLeak.gd`, no lo edites) se lee
  con `leak.get_state()`, que devuelve un `int` del enum `CoolantLeak.State` (`HEALTHY=0`,
  `WARNING=1`, `LEAKING=2`, `SEALED=3`, `DEPRESSURIZED=4` — importalo con
  `const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")` igual que ya hace
  `CoolantSystemStatusUI.gd` en su línea 10).

## Contrato

```gdscript
extends Control
class_name CoolantSchematicPanel
```

Sin exports obligatorios de configuración de layout — la topología del diagrama es **fija, de
autoría**, hardcodeada en el script (no genérica, no data-driven). Esto es intencional: el domo
tiene una topología concreta y conocida de antemano (dos circuitos con válvulas en varios pisos,
ver contexto abajo), no hace falta un sistema genérico de layout.

- Layout de referencia a dibujar: dos columnas verticales (circuito oeste / circuito este), cada
  una con una serie de nodos-punto apilados de abajo hacia arriba representando los pisos (planta
  baja + 5 pisos = 6 puntos por columna), conectados por una línea vertical entre puntos
  consecutivos. Un punto adicional a un costado (o conectando ambas columnas) representa la válvula
  de interconexión entre circuitos. No hace falta que el layout replique la geometría exacta del
  domo (eso lo ajustamos nosotros después si hace falta) — con que la estructura de "6 niveles por
  circuito, unidos por un puente" quede legible alcanza para esta tarea. Podés usar coordenadas
  hardcodeadas tipo `Vector2(80, 300 - i * 40)` para cada nivel `i` de 0 a 5.

- Cada punto = una válvula (dibujada como un pequeño círculo con `draw_circle`) coloreada según su
  `is_active` (verde = abierta, rojo = cerrada). Si hay más válvulas de las que caben en el layout
  fijo (por ejemplo la topología real termina teniendo más de 6 por lado), no hace falta que el
  panel las muestre todas — priorizá que compile y se vea ordenado con lo que tengas mapeado; el
  mapeo válvula→posición en el diagrama podés resolverlo por orden de aparición en el grupo
  `"coolant_valve"` ordenado con el mismo criterio que ya usa `CoolantSystemStatusUI._sort_by_floor_name`
  (mirá esa función, es un sort por nombre de nodo/padre `Floor_N`, replicala si te sirve o hacé un
  sort simple por nombre de nodo si el naming real no sigue ese patrón).

- Los tramos de tubería entre válvulas consecutivas (las líneas verticales, `draw_line`) se
  colorean según si hay fuga activa en ese tramo: buscar si alguna `CoolantLeak` cercana en la
  topología está en estado `LEAKING` o `WARNING` (magenta o amarillo) vs `HEALTHY`/`SEALED` (color
  neutro de tubería, celeste tenue) vs `DEPRESSURIZED` (gris apagado). No hace falta una
  correspondencia perfecta 1:1 tramo-a-fuga si la cantidad no calza exacto — es un diagrama de
  lectura rápida, no una simulación exacta.

- `_process(_delta)` o conectar a las señales `valve_state_changed`/`state_changed` de cada nodo
  relevante (igual patrón que `CoolantSystemStatusUI._setup_valve_rows()`) para llamar `update()`
  cuando cambia algo. Preferí señales sobre poll continuo si es sencillo de cablear; si es más
  simple para vos usar un timer/`_process` con throttle (releer estado cada ~0.2s en vez de cada
  frame), también es aceptable — es un panel de diagnóstico, no necesita 60Hz.

## Archivos permitidos

- `core_v2/things/CoolantSchematicPanel.gd` (nuevo)

## Archivos prohibidos

- Cualquier `.tscn` (no instancies este script en ninguna escena — eso lo hacemos nosotros después)
- `project.godot`
- `core_v2/things/CoolantSystemStatusUI.gd` (no lo edites, solo lo leés como referencia)
- `core_v2/systems/cryo/CoolantLeak.gd`, `core_v2/props/pipe/PipeValve.gd` (no los edites)
- Cualquier archivo fuera del listado en "Archivos permitidos"

## Reglas

- Godot 3.6 / GDScript 1.x. `yield`, nunca `await`.
- Sin dependencias nuevas, sin autoloads nuevos, sin assets/texturas nuevas — todo el dibujo es
  `_draw()` con primitivas nativas (`draw_circle`, `draw_line`, `draw_string`).
- Si `get_tree().get_nodes_in_group(...)` devuelve vacío (por ejemplo corriendo este panel aislado
  fuera de la escena real), `_draw()` no debe crashear — dibujar el layout fijo en gris neutro.

## Criterio de aceptación

No requiere test GdUnit3 automatizado (es un panel visual sin lógica de estado propia que valga la
pena testear aislada — toda la lógica de estado vive en `CoolantLeak`/`PipeValve`, que ya tienen
sus propios tests). Priorizá que el script no tenga errores de parseo/runtime: si podés, verificalo
instanciando el `Control` en un test mínimo GdUnit3 que solo confirme que `_ready()` y `_draw()` no
lanzan error con el árbol de escena vacío (grupos sin nodos) — `core_v2/tests/
test_coolant_schematic_panel.gd`, opcional pero valorado si es rápido de escribir.

## Qué NO hacer

- No repliques la lógica completa de `CoolantSystemStatusUI.gd` (las filas de texto) — este panel
  es el diagrama visual, complementario, no un reemplazo.
- No instancies nada en ninguna escena.
- No inventes un sistema de layout genérico/configurable — coordenadas hardcodeadas de un layout de
  dos columnas de 6 niveles está bien para esta tarea.
- No intentes replicar la geometría 3D exacta del domo — es un diagrama esquemático 2D de lectura
  rápida, no un mapa a escala.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
