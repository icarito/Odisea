# Odisea: El Arca Silenciosa — MVP Acto I

Proyecto Godot (3.x) enfocado en el MVP del Acto I: “El Sepulcro Criogénico”. Controlas a Elías (tercera persona) explorando la nave Odisea.

## Ejecutar
- Escena principal: `res://scenes/Menu.tscn`
- Requisitos: abre el proyecto en Godot 3.6.x para reimportar assets.

## Estructura (MVP)
- `scenes/levels/act1/`: escenas del Acto I (criogenia, pasillos, puentes)
- `scenes/common/Environment.tscn`: ambiente reutilizable (cielo, fog, glow)
- `players/elias/`: `Pilot.tscn` + `PlayerController.gd`
- `materials/`: materiales compartidos (interior y sombra falsa)
- `models/`: `Pilot.glb`
- `scripts/`: utilidades (`SceneSpawn.gd`, transiciones, cámara)
- `autoload/PlayerManager.gd`: jugador persistente entre escenas

## Diseño (resumen)
- Género: Plataformas 3D, Aventura, Puzzles
- Estética: Low-Poly Sci-Fi (influencias Tron/N64), niebla y neón
- Mecánicas Clave: movimiento 3ª persona de Elías, navegación precisa, transición a 0G en actos posteriores
- Actos: I Negación, II Laberinto, III Desafío, IV Decisión (ver `data/odisea_wiki.json`)

## Ejemplos y prototipos
Todo el material de pruebas y plantillas vive en `examples/` para mantener el MVP limpio:
- Plantillas de terceros, vehículos, escenas experimentales y assets de prototipos.

## Controles (por defecto)
- WASD: mover
- Espacio: salto
- Shift: sprint
- Click: ataque (placeholder)
- Botón derecho: rodar (placeholder)

## Notas
- El jugador ya no se instancia en cada escena; `PlayerManager` lo crea y reposiciona en el `SpawnPoint` de cada nivel.
- Para añadir nuevas escenas del Acto I, instancia `Environment.tscn`, coloca un `SpawnPoint` y (opcional) agrega triggers de transición.
