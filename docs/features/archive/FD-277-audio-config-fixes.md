# FD-277: Audio Config Fixes

Dos fixes de audio que NO requieren assets nuevos — solo cablear lo que ya existe.

## T1: BGM en bus "Music" (no "Master")

**Archivo:** `core_v2/autoloads/AudioManager.gd`

**Problema:** los dos `AudioStreamPlayer` internos de BGM se crean con `bus = "Master"` en las líneas 39 y 44. El proyecto ya tiene el bus `"Music"` definido en `default_bus_layout.tres` (`bus/1/name = "Music"`, con `send = "Master"`). Como la BGM está en Master, el slider "Music" de Opciones no la afecta.

**Cambio:** cambiar `bus = "Master"` por `bus = "Music"` en las líneas 39 y 44. Nada más.

## T2: Música del menú principal (Tin Cosmos.mp3)

**Asset ya existe:** `assets/music/Tin Cosmos.mp3`

**Qué falta:**
- Reproducir `Tin Cosmos.mp3` en loop cuando se abre la escena del menú principal.
- Detenerla al salir del menú (al cargar nivel/juego).
- Usar bus `"Music"` para que respete el slider de volumen.
- Si la escena del menú no tiene `AudioManager` como autoload, usar un `AudioStreamPlayer` local con `bus = "Music"` y `autoplay = false`, controlado por el script del menú.

## Constraints
- Godot 3.x / GDScript 1.x (`yield`, sin `await`, sin `@onready`).
- PR contra `trunk` (no mergear sin OK explícito de Sebastián).
- Test: (1) slider "Music" controla la BGM; (2) Tin Cosmos suena al abrir menú y se detiene al salir.

## Referencias
- `core_v2/autoloads/AudioManager.gd` líneas 39 y 44 (BGM players)
- `default_bus_layout.tres` (bus "Music" ya definido)
- `assets/music/Tin Cosmos.mp3` (confirmado presente)
