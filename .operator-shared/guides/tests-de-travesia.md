# Tests de travesía con el piloto real

Cómo escribir un test que recorre un nivel con `Pilot_v2` sin reventar el presupuesto de CI.

- **El job core corre en 8 shards alfabéticos con tope de 180 s por shard.** Un shard que
  agota el tope devuelve `rc=124` y anula el reintento aislado que rescata los flakes
  conocidos (ringhub, touch): el job queda rojo por tests ajenos al cambio. El shard de
  `test_machine_*` ya consume ~147 s en `main`; cualquier suite nueva ahí debe sumar pocos
  segundos.
- **Los tests de física corren a tiempo real** (60 ticks por segundo de reloj). `Engine.time_scale`
  no sirve para acelerarlos: en Godot 3 escala el delta que reciben `move_and_slide` y el
  servidor de física, pero el jugador simula con `step(1.0 / iterations_per_second, input)`, así
  que la simulación cambia.
- **Receta para rutas de geometría estática:** `pilot.set_physics_process(false)` y llamar
  `pilot._physics_process(0.0)` varias veces por frame del motor, cediendo un `physics_frame`
  cada N ticks. Es el mismo controlador, el mismo dt y la misma colisión, sin esperar al reloj
  (`test_machine_bay_parkour.gd`: 43 s → 5 s). No vale si la ruta depende de cuerpos rígidos,
  plataformas móviles o áreas: esos sí necesitan el paso del servidor de física.
- **Una suite que comparte la escena entre tests debe devolver al piloto al spawn** antes de
  una travesía: los tests previos lo dejan donde cayó.
