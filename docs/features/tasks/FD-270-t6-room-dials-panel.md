# FD-270 T6 (JM2): `RoomDialsPanel` — dials de temperatura/presión/toxicidad

## Objetivo

Crear `core_v2/things/RoomDialsPanel.gd` (+ `.tscn` mínimo si hace falta, ver abajo): un `Control`
que dibuja tres dials tipo aguja/arco — temperatura, presión, contaminación ("toxicidad") — leyendo
en vivo el estado de un nodo `Room3D` ya existente en el proyecto.

## Contexto del sistema

Motor Godot 3.6 / GDScript 1.x (`extends`/`class_name`, `export()` con paréntesis, `yield` nunca
`await`). Este panel va a vivir dentro del `Viewport` de un terminal holográfico en pantalla (no lo
edites, es trabajo nuestro instanciarlo ahí), así que tiene que funcionar como cualquier `Control`
normal — nada de lectura de input de mouse/teclado, es solo lectura y dibujo.

`core_v2/systems/room/Room3D.gd` (**no lo edites**, ya existe y está terminado) expone:

```gdscript
export(float) var temperature: float = 20.0      # grados, setget set_temperature
export(float) var pressure: float = 1.0          # setget set_pressure
export(float) var contamination: float = 0.0     # 0..1, setget set_contamination ("toxicidad")

export(float) var freezing_point: float = 0.0
export(float) var lethal_cold: float = -25.0
export(float) var fog_threshold: float = 0.3
export(float) var hazard_threshold: float = 0.7
export(float) var overpressure: float = 2.4

signal temperature_changed(new_value)
signal pressure_changed(new_value)
signal contamination_changed(new_value)
```

y métodos de consulta ya implementados: `is_freezing()`, `is_lethal_cold()`, `is_fog_active()`,
`is_hazard_active()`, `is_overpressured()` (todos `bool`, sin argumentos).

## Contrato

```gdscript
extends Control
class_name RoomDialsPanel

export(NodePath) var room_path: NodePath
```

- `_ready()`: resolver `room_path` a un nodo (`get_node_or_null`), guardarlo en `var _room: Node`.
  Si `_room` no es `null` y tiene las señales `temperature_changed`/`pressure_changed`/
  `contamination_changed`, conectate a las tres con `connect(..., self, "_on_room_value_changed")`
  (podés pasar un solo callback que solo llame `update()` — no hace falta lógica distinta por
  señal). Llamar `update()` una vez al final de `_ready()` para el estado inicial.

- `_on_room_value_changed(_new_value = null) -> void`: simplemente llama `update()` (el redraw de
  Godot con `Control._draw()` necesita que llames `update()` explícitamente cada vez que cambian
  los datos — no se redibuja solo).

- `_draw() -> void`: implementación del dibujo. Referencia de layout (podés ajustar proporciones,
  el objetivo es que se lea, no pixel-perfect):
  - Tres arcos, uno por variable, dispuestos horizontalmente o en columna (elegí lo que se vea más
    ordenado dado el tamaño típico de un panel de diagnóstico, algo como 300x400 o similar — no
    hace falta que sea configurable, hardcodealo).
  - Cada arco: usar `draw_arc(center, radius, angle_from, angle_to, point_count, color, width)`
    (API nativa de `CanvasItem` en Godot 3.6, no hace falta implementarla vos). Un arco de fondo
    gris tenue (rango completo) y un arco de valor superpuesto cuyo `angle_to` se calcula
    normalizando el valor actual contra un rango razonable:
    - Temperatura: normalizar contra `[lethal_cold, freezing_point + 40.0]` aprox (o algo similar
      que deje ver bien el rango relevante — usá los thresholds de `Room3D` como referencia de
      escala, no un rango inventado sin relación).
    - Presión: normalizar contra `[0.0, overpressure * 1.2]`.
    - Contaminación: ya viene en `0..1`, no hace falta normalizar.
  - Color del arco de valor según estado, usando los métodos de consulta de `Room3D` (no
    reimplementar los thresholds a mano):
    - Temperatura: rojo/naranja si `is_lethal_cold()`, celeste si `is_freezing()`, blanco/verde si
      no.
    - Presión: rojo si `is_overpressured()`, verde si no.
    - Contaminación: rojo si `is_hazard_active()`, amarillo si `is_fog_active()`, verde si no.
  - Una etiqueta de texto simple con `draw_string()` bajo cada dial mostrando el valor numérico
    (`"%.1f°C"`, `"%.2f atm"`, `"%d%%"` por ejemplo) — usá una `DynamicFont`/`Font` por defecto,
    no hace falta cargar una fuente custom (`get_font("font")` de un tema por defecto sirve, o
    dejá que Godot use la fuente default si no se especifica ninguna).

- Si preferís separar el dibujo de un solo dial en una función privada `_draw_dial(center, radius,
  value_normalized, color, label)` para no repetir código tres veces, adelante — es la opción más
  simple y es la recomendada.

## Archivos permitidos

- `core_v2/things/RoomDialsPanel.gd` (nuevo)

## Archivos prohibidos

- Cualquier `.tscn` (no instancies este script en ninguna escena — eso lo hacemos nosotros a mano
  después dentro del terminal holográfico del domo)
- `project.godot`
- `core_v2/systems/room/Room3D.gd` (no lo edites, solo lo leés)
- `core_v2/things/CoolantSystemStatusUI.gd` (existe, es un panel hermano que ya muestra estado de
  válvulas/tanque/fisuras con `Label`s — no lo edites ni dupliques su lógica, este panel es aparte)
- Cualquier archivo fuera del listado en "Archivos permitidos"

## Reglas

- Godot 3.6 / GDScript 1.x. `yield`, nunca `await`.
- Sin dependencias nuevas, sin autoloads nuevos, sin texturas/assets nuevos — todo el dibujo es
  `_draw()` con primitivas nativas (`draw_arc`, `draw_string`, `draw_line`, etc.).
- Si `room_path` no resuelve o `_room` es `null`, `_draw()` no debe crashear — dibujar los arcos en
  gris/estado neutro o simplemente no dibujar nada, sin errores en consola.

## Criterio de aceptación

No hace falta un test GdUnit3 automatizado para el dibujo en sí (es visual), pero si el script
tiene lógica de normalización de valores que se pueda testear sin render (por ejemplo una función
pura `_normalize_temperature(value: float) -> float` que devuelva `0..1`), extraela como función
separada y agregá un test simple en `core_v2/tests/test_room_dials_panel.gd` que verifique que los
extremos del rango dan `0.0` y `1.0`. Si no separás esa lógica, no hace falta el test — priorizá
que el panel se vea bien y no crashee sobre que exista un test.

## Qué NO hacer

- No dupliques el panel de texto que ya existe (`CoolantSystemStatusUI.gd`) — este es un panel
  visual nuevo y complementario, no un reemplazo.
- No instancies nada en ninguna escena.
- No inventes un layout configurable por exports — coordenadas y tamaños hardcodeados están bien
  para esta tarea (YAGNI, es un panel de diagnóstico de una sola escena).

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
