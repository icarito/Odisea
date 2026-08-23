# FD-273 T1: Migrar ColdRuptureEvent a OYSTrigger + OYS (brief para Jules)

## ⚠️ ANTES DE EMPEZAR — Godot 3 vía apt (obligatorio)

En Odisea SIEMPRE hay que instalar Godot 3 con `apt` en tu ambiente antes de correr
cualquier test. El proyecto es **Godot 3.x** (`project.godot` con `config_version=4`),
no Godot 4. Verificá que `godot` (o `godot3`) esté en el PATH y sea la versión 3.x
antes de ejecutar el runner (`./test_prop.sh` o el runner de `core_v2`). Si no está,
instalalo con apt y recién después corré los tests.

## Contexto — qué está mal con el patrón actual

`ColdRuptureEvent.gd` es un `Spatial` monolítico que hace TODO en GDScript: detecta
el cuerpo con su propio `TriggerArea`, sortea fugas (`RandomLeakSeeder`), dispara
sonidos, explosiones y screen shake, todo hardcodeado. **Ese NO es el patrón.**

El patrón correcto:

```
OYSTrigger (área)  →  ejecuta  →  cold_rupture.oys (guion)
                                    │  CALL actor "método" (granos gruesos)
                                    ▼
                          ColdRuptureDirector (nodo actor OYS, GDScript mínimo)
```

- El trigger es un `OYSTrigger` que llama a un `.oys`. Nada de `TriggerArea` propio.
- La secuencia y el timing viven en el `.oys`. El GDScript solo expone "actuadores".
- El director se registra con `SessionManager.register_oys_actor("ColdRupture", self)`.

## Referencias exactas (verificadas — no inventes APIs)

- Registro de actores: `core_v2/autoloads/SessionManager.gd`
  - `register_oys_actor(name, node)` (línea ~3906), `get_oys_actor(name)` (~3915),
    `unregister_oys_actor(name)` (~3924).
- Resolución de `CALL`: `core_v2/systems/OYS_Interpreter.gd` (~línea 526):
  `CALL <Actor> "<metodo>"` → `actor = SessionManager.get_oys_actor(method)`; el
  primer arg (`args[0]`) es el nombre real del método; el resto son argumentos.
- `VCAMERA look_at=` resuelve **un nodo**, no una posición:
  `OYS_Interpreter._resolve_vcamera_target()` (~línea 1764). Por eso hace falta el
  marcador `RuptureFocus` (un `Spatial`) que el director reposiciona.
- `find_vcamera()` busca en el grupo `vcamera`: `core_v2/autoloads/CinematicManager.gd:219`.
- Crossfade privado existente: `AudioManager._crossfade_to(stream, pitch, vol, time, zone)`
  (~línea 279). **No es público** y recibe un `AudioStream`, no un nombre.
- `PLAY_SOUND` en `OYS_Interpreter.gd` (~línea 363) solo funciona si hay un nodo
  (`play_sfx()`/`play()`) o un MixingDeskSound (plugin desactivado). → la alarma y
  las explosiones deben salir por métodos del director, no por `PLAY_SOUND` crudo.

## Lo que hay que IMPLEMENTAR (los gaps — no intentes "usar lo que no existe")

1. **`OYSTrigger.trigger_from_script()`** (`core_v2/components/OYSTrigger.gd`):
   método público que ejecute el mismo camino que `_on_zone_entered`
   (`_run_oys_on_body(body, script_file)`), pero sin esperar `body_entered`.
   Mantener `trigger_once` y el skip en replay/respawn. Para el "BGM terminó",
   emitir una señal en `AudioManager` (o `BGMZoneV2`) cuando el BGM finalice y
   conectar esa señal al trigger.
2. **`AudioManager.crossfade_to_song(song_name, fade_time=1.0)`** (público):
   cargar el stream por nombre y reutilizar `_crossfade_to()`. (Preferí esta opción
   sobre registrar una `BGMZoneV2` temporal, que es más indirecta.)
3. **`ColdRuptureDirector`** (`core_v2/systems/cryo/ColdRuptureDirector.gd`, nuevo):
   - `extends Node` (o `Spatial` si necesita posición); `class_name ColdRuptureDirector`.
   - `_ready()` → `SessionManager.register_oys_actor("ColdRupture", self)`; al salir
     del árbol, `unregister_oys_actor`.
   - Estado determinista + snapshot/replay (grupo `replay_sync`): `consumed`,
     fugas activas (delega a `RandomLeakSeeder`), `last_explosion_pos`.
   - Métodos granulares (lo que llama el OYS):
     - `play_alarm()`
     - `spawn_explosion()` → instancia `explosion_scene`, posiciona, actualiza
       `last_explosion_pos` (y devuelve la posición).
     - `focus_last_explosion()` → mueve el marcador `RuptureFocus` a `last_explosion_pos`.
     - `crossfade_heartbeat()` → `AudioManager.crossfade_to_song("Mechanical Heartbeat.mp3")`.
   - **Nada de "cuándo" acá**: solo "qué". El orden y los `WAIT` van en el `.oys`.
   - **Sin `randf()`**: el azar pasa por `RandomLeakSeeder` (seed fijo). Snapshot/restore reproducible.
4. **Dome_Intro.tscn**: reemplazar el `TriggerArea` de `ColdRuptureEvent` por un
   `OYSTrigger` con `script_file="res://core_v2/levels/interiors/cold_rupture.oys"`;
   instanciar `ColdRuptureDirector`, el marcador `RuptureFocus` (Spatial vacío), y un
   rig VCamera en el grupo `vcamera` (si no hay uno global instanciado).
5. **`cold_rupture.oys`** (nuevo) — ver bosquejo abajo.
6. **Asset "Mechanical Heartbeat.mp3"**: no existe en el repo. Agregalo o, si no
   podés, usá un stream existente y dejalo señalado en el PR con un TODO.

## Sintaxis OYS a usar (verificada — copiala tal cual, sin inventar)

- `CALL ColdRupture "spawn_explosion"` — actor + método, sin args (el array de args
  está roto en el parser: no uses `CALL X "m" [1,2,3]`).
- `CAMERA_SHAKE duration=0.4 amplitude=0.1 frequency=30 roll=1.2`
- `ZOOM amount=-0.2 duration=0.6` (verificar signo: negativo ≈ zoom in)
- `VCAMERA name="RuptureCam" duration=0.6 look_at="RuptureFocus"`
- `VCAMERA_RETURN duration=0.8`
- `CINEMATIC` / `INTERACTIVE` (⚠️ `INTERACT` es otro comando, NO lo uses como salida de cinemático)
- `WAIT <segundos>`

## Bosquejo del `.oys` (el esqueleto; los valores los calibrás después)

```
CINEMATIC
CALL ColdRupture "play_alarm"
ZOOM amount=-0.2 duration=0.6
WAIT 1.2
CALL ColdRupture "spawn_explosion"
CAMERA_SHAKE duration=0.4 amplitude=0.1 frequency=30 roll=1.2
CALL ColdRupture "focus_last_explosion"
VCAMERA name="RuptureCam" duration=0.6 look_at="RuptureFocus"
WAIT 0.8
CALL ColdRupture "spawn_explosion"
CAMERA_SHAKE duration=0.5 amplitude=0.12 frequency=28 roll=1.5
CALL ColdRupture "crossfade_heartbeat"
WAIT 2.0
VCAMERA_RETURN duration=0.8
INTERACTIVE
```

## Reglas

- Godot 3.x / GDScript 1.x: `yield`, nunca `await`. Sin `@onready`.
- Determinismo: sin `randf()` en el director; azar vía `RandomLeakSeeder` (seed fijo).
- Composición sobre herencia; señales, no `get_parent()`.
- Cada componente < 200 líneas haciendo una sola cosa.

## Archivos permitidos

- `core_v2/components/OYSTrigger.gd`
- `core_v2/systems/cryo/ColdRuptureDirector.gd` (nuevo)
- `core_v2/autoloads/AudioManager.gd`
- `core_v2/levels/interiors/Dome_Intro.tscn`
- `core_v2/levels/interiors/cold_rupture.oys` (nuevo)

## Archivos prohibidos

- Reescribir `ColdRuptureEvent.gd` entero sin necesidad.
- Cualquier `.tscn` fuera de `Dome_Intro.tscn`.
- `project.godot`.

## Criterio de aceptación

1. Entrar al área dispara la secuencia en orden y vuelve a `INTERACTIVE`.
2. Editable ajustando solo el `.oys` (sin recompilar).
3. Se puede disparar desde fuera del área (ej. BGM terminó).
4. `CALL ColdRupture "..."` resuelve los métodos del director sin errores.
5. `VCAMERA look_at="RuptureFocus"` apunta a la última explosión aleatoria.
6. El runner de `core_v2` no rompe las pruebas existentes.

Cuando termines, publicá el PR contra `main` con el FD y el diff. **No mergear sin OK explícito.**
