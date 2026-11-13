# FD-273: Migrar ColdRuptureEvent a OYSTrigger + OYS (ruptura guionada/cinemática)

**Status:** Design (revisado 2026-08-23 — sintaxis OYS corregida contra el parser/interpreter)
**Priority:** High (P0.2)
**Effort:** Medium
**Parent:** FD-255 (Maestro) / FD-266 (semántica del puzle) / FD-270 (pipe network flow)

## Problem

`core_v2/systems/cryo/ColdRuptureEvent.gd` es un `Spatial` monolítico que dispara
(área propia), decide gameplay (fugas vía `RandomLeakSeeder`) y dirige presentación
(sonido, explosiones, screen shake) todo hardcodeado. Tres límites:

1. **No es guionable** — la secuencia (alarma → zoom → explosión → cámara → BGM)
   vive en GDScript, no en un `.oys`.
2. **No se puede gatillar desde afuera** — solo responde al `body_entered` de su
   `TriggerArea`; no hay forma de dispararla por "se acabó la BGM" u otro evento.
3. **Mezcla estado y presentación** — el snapshot de replay convive con efectos,
   frágil para el determinismo de Core V2.

## Solution (arquitectura objetivo)

Separar en tres capas, coordinadas por OYS:

```
OYSTrigger (área, reemplaza TriggerArea manual)
   └─ script_file = "res://core_v2/levels/interiors/cold_rupture.oys"
        │  orquesta con CALL / VCAMERA / CAMERA_SHAKE / ZOOM / WAIT
        ▼
ColdRuptureDirector (nodo actor OYS, GDScript mínimo = "qué")
   └─ registrado: SessionManager.register_oys_actor("ColdRupture", self)
```

- **OYSTrigger** (`core_v2/components/OYSTrigger.gd`): el área que dispara el `.oys`.
- **ColdRuptureDirector** (`core_v2/systems/cryo/ColdRuptureDirector.gd`, nuevo):
  conserva el estado determinista (`consumed`, fugas activas vía `RandomLeakSeeder`,
  `last_explosion_pos`) y expone métodos de grano grueso. Nada de "cuándo" vive acá.
- **`cold_rupture.oys`** (nuevo): el guion. **Todo lo ajustable vive acá.**

`ColdRuptureEvent.gd` puede conservar funciones de bajo nivel (spawn de explosión,
activar fuga), pero **el disparador y la secuencia dejan de ser suyos**.

### Secuencia objetivo

1. Alarma lejana (vía director `play_alarm()`, NO `PLAY_SOUND` — ver gaps).
2. Zoom in (`ZOOM`).
3. Primera explosión (`CALL ColdRupture "spawn_explosion"`) + su `CAMERA_SHAKE`.
4. Cámara mira al origen (`VCAMERA ... look_at="RuptureFocus"`).
5. Segunda explosión + su `CAMERA_SHAKE`.
6. Crossfade a "Mechanical Heartbeat.mp3" (director → AudioManager).

Cada explosión lleva **su propio shake**.

### Fisuras aleatorias + LookAt a la última explosión

Las fugas son random (`RandomLeakSeeder`, seed determinista); el OYS no conoce la
posición de antemano. El director guarda `last_explosion_pos` y reposiciona un
`Spatial` marcador `RuptureFocus` antes de cada `VCAMERA look_at="RuptureFocus"`.

## Lo que NO se puede hacer aún (sincerado — Jules debe implementarlo)

1. **`OYSTrigger` no tiene `trigger_from_script()`.** Hoy solo dispara en
   `_on_zone_entered()` (ver archivo). Hay que añadir un método público que ejecute
   el mismo camino (`_run_oys_on_body()`) sin esperar `body_entered`, respetando
   `trigger_once` y el skip de replay/respawn. → **nuevo método requerido.**
2. **`AudioManager` no tiene crossfade público por nombre de canción.** Existe
   `_crossfade_to(stream, pitch, vol, time, zone)` pero es **privado** y recibe un
   `AudioStream` ya cargado, no un nombre. → **nuevo método público
   `crossfade_to_song(song_name, fade_time=1.0)`** que cargue el stream y reutilice
   `_crossfade_to()`. El director lo invoca vía `CALL ColdRupture "crossfade_heartbeat"`.
3. **`VCAMERA look_at=` resuelve un NODO existente en el árbol, no una posición.**
   (`OYS_Interpreter._resolve_vcamera_target()` → busca nodo por nombre/path). Por eso
   hace falta el marcador `RuptureFocus` que el director reposiciona.
4. **Dome_Intro no tiene ninguna VCamera en el grupo `vcamera`.** `find_vcamera()`
   (`CinematicManager.gd:219`) busca en el grupo `vcamera`; si no existe, `VCAMERA`
   imprime "not found". El rig `VCameraSystem.tscn` existe pero **no está instanciado**
   en `Dome_Intro.tscn`. → **hay que añadir un rig VCamera (grupo `vcamera`) a la
   escena**, o reutilizar uno global si lo hay instanciado.
5. **`PLAY_SOUND "nombre"` NO suena por sí solo.** El interpreter intenta
   `_resolve_node(nombre)` (un nodo con `play_sfx()`/`play()`) y, si no, cae a
   `AudioManager.play_sound(name, ZERO)`, que **solo funciona si existe MixingDeskSound**
   (el plugin está desactivado) — si no, solo imprime warning. → la alarma/explosión
   deben salir por **métodos del director** (que usan `AudioStreamPlayer3D` reales ya
   presentes, ej. `RuptureSound`), no por `PLAY_SOUND` crudo.
6. **`CALL` con array de args está roto.** El parser separa por comas sin respetar
   corchetes: `CALL X "m" [10,20,30]` produce basura. → **usar `CALL Actor "metodo"`
   sin args, o args escalares simples** (un número/string). La lógica que necesite
   posición se resuelve dentro del método del director.
7. **"Mechanical Heartbeat.mp3" NO existe en el repo.** (grep vacío; solo existe
   `assets/music/_unused/With Each Heartbeat.mp3`). → hay que añadir el asset y
   referenciarlo; o, mientras tanto, usar un stream ya existente y dejarlo señalado.

## Sintaxis OYS corregida (verificada contra el parser/interpreter)

| Comando | Sintaxis real | Notas |
|---|---|---|
| `CALL` | `CALL <Actor> "<metodo>" [args escalares]` | Actor = nombre registrado en `SessionManager.get_oys_actor()`. Primer token tras el actor es el método. |
| `VCAMERA` | `VCAMERA name="..." duration=... look_at="<nodo>"` | `look_at` = nodo (grupo `vcamera`). `duration` default 1.0. |
| `VCAMERA_BLEND` | `VCAMERA_BLEND name="..." duration=...` | transición entre vcameras. |
| `VCAMERA_RETURN` | `VCAMERA_RETURN duration=...` | vuelve al jugador. |
| `CAMERA_SHAKE` | `CAMERA_SHAKE duration=0.4 amplitude=0.1 frequency=30 roll=1.2` | también posicional `CAMERA_SHAKE 0.4 0.1 30 1.2`. |
| `VCAMERA_SHAKE` | `VCAMERA_SHAKE translation="(0.25,0.25,0)" rotation="(0,0,5)" intensity=1.0 duration=1.0 frequency=16` | shake "rico" (usado en `intro.oys`). |
| `ZOOM` | `ZOOM amount duration` | `amount` delta por frame; **verificar signo** (negativo ≈ zoom in). |
| `CINEMATIC` / `INTERACTIVE` | `CINEMATIC` … `INTERACTIVE` | entrar/salir modo cinemático. (⚠️ `INTERACT` es OTRO comando, de interacción con nodo — no confundir.) |
| `WAIT` | `WAIT <segundos>` | también `WAIT_FRAMES <n>` / `WAIT <n>frames`. |

## Files to Modify

- `core_v2/systems/cryo/ColdRuptureDirector.gd` (nuevo) — actor OYS determinista
- `core_v2/components/OYSTrigger.gd` — añadir `trigger_from_script()`
- `core_v2/autoloads/AudioManager.gd` — añadir `crossfade_to_song(song_name, fade_time=1.0)`
- `core_v2/levels/interiors/Dome_Intro.tscn` — OYSTrigger + director + marcador `RuptureFocus` + rig VCamera (grupo `vcamera`)
- `core_v2/levels/interiors/cold_rupture.oys` (nuevo) — el guion
- asset: añadir `Mechanical Heartbeat.mp3` (o reusar uno existente, señalado)

**Fuera de alcance:** semántica del puzle (FD-266), arte/geometría, resto del bloque P1.

## Verification

1. Entrar al área dispara la secuencia completa en orden y vuelve a `INTERACTIVE`.
2. Replay determinista: mismo seed ⇒ misma secuencia, sin `randf()` en el director.
3. Gatillar desde afuera (BGM terminó) arranca sin `body_entered`.
4. `CALL ColdRupture "..."` resuelve métodos del director sin errores.
5. `VCAMERA look_at="RuptureFocus"` apunta a la última explosión aleatoria.
6. El runner de tests de `core_v2` no rompe las pruebas existentes.
