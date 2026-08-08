# radial_menu (vendored)

Origen: https://github.com/tavurth/godot-radial-menu — rama `3.x`
(commit `8a8e01a5121474e0b2e7c4ae78721ff59588f2ba`, 2022-03-06). MIT, ver `LICENSE.txt`.

La rama por defecto del repo (`4.x`) es Godot 4 y no sirve acá: usar siempre `3.x`.

## Codigo sin modificar

Los archivos del addon estan **tal cual upstream**. Si hace falta cambiarlos, anotarlo acá.

## Como lo usa Odisea

`core_v2/ui/radial/RadialSelectorV2.gd` lo envuelve. Del addon se usa el **anillo**:
`RadialMenu.tscn` mas `selector.shader`, que dibuja el arco de seleccion. El resto
lo maneja el wrapper, por cuatro razones concretas:

1. **El puntero.** Upstream, `CursorPos.gd` lee el puntero del sistema
   (`get_global_mouse_position`) y selecciona con click. Eso obligaria a soltar la
   captura del mouse cada vez que se abre el menu. El wrapper apaga
   `set_process_input()` de `CursorPos` y del propio `RadialMenu`: el dueño del
   dial proyecta hacia donde apunta la camara sobre el plano del holograma y pasa
   el impacto en pixeles del viewport (`point_at`). El mouse nunca se libera.

2. **"Nada seleccionado".** Upstream siempre hay un indice: `get_index()` clampea
   al mas cercano, mire donde mire el jugador. Acá existe `NONE`, y `confirm()`
   se traga la tecla: sin eso, un click con la camara mirando para otro lado
   elegiria el piso que quedo mas a mano. Ojo con el reves: **dentro** del
   holograma nunca hay `NONE`. Cualquier direccion enfoca algun piso — incluido
   la mitad que el dial no usa, que cae al extremo mas cercano. Un dial con
   huecos se siente roto, no estricto. El dueño decide si el jugador esta
   mirando el holograma; de ahi para adentro todo es rumbo.

3. **El indice.** `CursorPos.get_index()` hace `round(angle / step - 1)` con clamp.
   Esa formula solo coincide con `place_buttons()` para ciertas cantidades de
   opciones — con 3 opciones cada seleccion sale corrida. El wrapper coloca las
   opciones el mismo y usa la inversa exacta de su propia formula, asi anda con
   cualquier cantidad. Cubierto por `core_v2/tests/test_radial_selector.gd`.

4. **El orden.** `place_buttons()` reparte en los 360° desde un angulo fijo. Acá
   el dial usa media vuelta: la opcion 0 va a las 6 en punto y sube en sentido
   horario por las 9 hasta las 12. La mitad derecha queda libre para el readout
   de nivel.

5. **Estado, no solo eleccion.** El addon solo sabe de opciones. Este dial ademas
   lleva una aguja apuntando a donde esta el carro de verdad — `set_level()` toma
   fracciones, asi que entre pisos la aguja queda entre dos etiquetas — y un
   readout que se desliza en Y cuando el nivel cambia.

Cuatro detalles del shader:

- Sus setters (`set_color_bg`, `set_width_max`, …) hacen
  `if not len(self.get_children()): return`, y `get_children()` esta sobrescrito
  para descontar los nodos internos. Con las opciones fuera del contenedor esa
  lista queda vacia y ningun parametro se aplicaria, asi que el wrapper los
  escribe directo sobre el material del `Background` (duplicandolo, porque
  `selector.tres` es compartido y viene con un bevel rojo de debug prendido).
- `cursor_deg` se compara contra `atan()`, que devuelve -PI..PI. Pasarle un angulo
  fuera de ese rango deja el arco corrido hasta medio sector, asi que el wrapper
  normaliza antes de mandarlo.
- El track (`color_bg`) se deja **transparente**: el shader lo dibuja en todo el
  circulo y no tiene uniform de span, asi que en un dial de media vuelta la mitad
  sin usar saldria como un pedazo de anillo pelado. Sin track, los unicos elementos
  del anillo son la cuña de la opcion apuntada y la aguja de nivel.
- `cursor_size` es medio ancho y se topea a medio paso (`_step() * 0.5`). Fijo, se
  desborda sobre los pisos vecinos apenas crece la cantidad de opciones o se acorta
  el arco, y la cuña deja de decir a que piso pertenece.

## Consumidor

`core_v2/props/elevator/ElevatorFloorSelector.tscn` — el selector de piso dentro de
la cabina del ascensor (`core_v2/props/machinery/ElevatorProp.tscn`).
