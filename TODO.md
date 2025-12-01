# TODO

## Acto I MVP
- [x] Menu minimal que inicia `scenes/levels/act1/criogenia.tscn`.
- [x] Reubicar `Pilot.tscn` a `players/elias/` y conectar `PlayerController.gd`.
- [x] Crear `Environment.tscn` reutilizable (sky, fog, glow, ambient).
- [x] Prototipos: `pasillo.tscn`, `puente.tscn`, `pasillo2.tscn`, `puente2.tscn` con transiciones.
- [x] Sombra falsa del jugador (RayCast + MeshInstance + material transparente).
- [ ] Materiales interiores reutilizables: `MetalPaint`, `Rubber`, `WallPanel`.
- [ ] Limpieza de assets de ejemplo y tutorial; mover a `examples/` en forma funcional.
- [x] Mover `Pilot.glb` a `models/` y reimportar en Godot.

## Notas de diseño
- Se crearon dos pasillos/puentes para explorar variantes de tamaño/iluminación y probar transiciones en ambas direcciones.
- Actualmente cada escena instancia `Pilot` por simplicidad. Para persistencia del jugador entre escenas, considerar un `Autoload` que gestione el `Player` y use `change_scene_to` sin recrearlo.

## Próximos pasos
1. Ajustar `players/elias/PlayerController.gd` (suavizado/drag).
2. Configurar transiciones de retorno entre `pasillo*` y `puente*`.
3. Crear carpeta `models/` y mover `Pilot.glb` (cuando esté disponible), actualizar rutas y reimportar.
4. Añadir materiales interiores y aplicar a suelos/paredes.
