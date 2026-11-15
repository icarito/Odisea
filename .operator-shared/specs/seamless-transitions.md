# Spec: Transiciones seamless — contrato e invariantes

**Estado:** v1
**Fecha:** 2026-11-14
**Owner:** sesión `pulido-del-vertical-3`
**Referencia:** FD-021 (scene transition), FD-032 (seamless startup), FD-297 (HUD), FD-289 (domo→hangar)
**Pedido:** "las transiciones deberían ser todas completamente seamless. Nada de fade a negro, pantallas de carga ni cortes de cámara entre áreas."

Esta spec define el **contrato** y las **invariantes** del mecanismo común de transición seamless. No describe implementación interna de SceneManager (eso vive en el código y en la sesión); acá se define el qué, para que cualquier productor (airlock, portal, tubo, tránsito, bahía, hangar) migre sin ambigüedad.

---

## 1. Definiciones

- **Buffer físico de transición**: el espacio del mundo por el que el jugador transita físicamente entre dos áreas (cámara de airlock, tubo peatonal, cápsula de tránsito, pozo de descenso, umbral de puerta doble). Es el lugar donde el cambio de escena queda oculto.
- **Transición seamless**: cambio de escena sin fade a negro, sin pantalla de carga, sin corte de cámara ni de audio, y sin que `current_scene` sea `null` en ningún frame. El swap ocurre **detrás de las puertas cerradas** del buffer.
- **Espera diegética**: si la escena destino no terminó de precargarse cuando el jugador llega al umbral de salida del buffer, el mundo espera *dentro de la ficción*: las puertas no abren, la luz de ciclo queda roja/parpadeante, nunca una pantalla negra.
- **Lift del jugador**: durante el swap, el nodo del jugador se re-parenta a un autoload persistente (`AirlockManager`), de modo que ni la cámara ni la pose se pierden cuando la escena vieja se libera.

## 2. Contrato del productor

Todo productor de transición que quiera ser seamless debe:

1. **Precargar** la escena destino en background al entrar al buffer: `SceneManager.request_scene_preload(destino)` (o pasar `_preloaded_scene` ya cargada).
2. **Armar el lift** inmediatamente antes de `goto_scene`: `AirlockManager.notify_transition(destino)`.
3. **Pedir modo seamless**: `goto_scene(destino, {"transition": "seamless", ...})`.
4. **Conservar pose y velocidad relativas al buffer** en `state_data` (`airlock_relative_transform`, `airlock_relative_velocity`, `camera_yaw/pitch`, `camera_relative_forward`, `target_airlock_path`, `target_airlock_exit_door`) cuando el destino tiene un airlock espejo; si no, `preserve_player_state=false` + `target_spawn_id` para aparición por spawn.
5. **Gatear el swap** de forma **determinista**: el criterio "el jugador llegó al umbral" y "la carga terminó" debe medirse en `_physics_process` (el grabador OYS cuantiza por tick de física). **No** gatear el disparo en esperas asíncronas de loader cuyo instante de finalización varíe entre grabación y replay (ver invariante 3).
6. **Gating de re-disparo**: el airlock/trigger de destino debe ignorar entradas mientras `SceneManager.is_transitioning()` y durante `POST_TRANSITION_GRACE_FRAMES` desde `scene_ready` (evita el rebote por overlap del jugador sostenido con el airlock espejo de la escena nueva).

### Excepción documentada

Los productores **instantáneos** (p.ej. `TubeAirlock`) pueden disparar apenas entra el jugador, sin esperar la precarga: el swap seamless oculta la carga (el jugador está sostenido y la cámara sigue viva). La espera diegética queda reservada a productores con umbral de tránsito (p.ej. `AirlockZoneV2`), que sí pueden esperar a `_scene_ready`. Esta compensación existe para no romper el determinismo de replay (medido: drift ~1–2 cm sobre el umbral al esperar la precarga).

## 3. Invariantes del mecanismo

1. **Nunca en negro**: durante una transición seamless, `current_scene` nunca es `null`; la escena nueva se agrega **antes** de liberar la vieja (swap add-before-free), y el jugador sostenido mantiene la cámara activa (`force_camera_current`).
2. **El jugador sobrevive al swap**: si el productor no arma el lift (`notify_transition`), el mecanismo no garantiza seamless; en ese caso cae al camino legacy (posible fade). El modo `seamless` **exige** el lift.
3. **Determinismo y replay**: la lógica de transición que afecta estado físico corre en `_physics_process`. El disparo del swap debe ocurrir en el mismo tick de física entre grabación y replay; el input y la pose deben ser reproducibles. Cualquier espera por reloj de pared o por loader asíncrono que desalinee el tick queda prohibida como gate de disparo.
4. **El audio cruza sin corte**: en modo seamless no se hace fade-out de la BGM actual; al llegar, la zona de BGM del destino toma el control con refresco `0s` (sin hueco ni reinicio).
5. **Sin sistemas paralelos**: el mecanismo extiende `SceneManager` y `AirlockManager`; ningún productor crea su propio loader/swap.
6. **La cámara no cambia de relación**: el rig y el spring arm son los del jugador; el buffer no introduce cámaras propias (salvo las cinemáticas autorizadas, p.ej. descenso al hangar).

## 4. Inventario de transiciones del slice y estado

| Transición | Productor | Buffer | Estado |
|---|---|---|---|
| Boot → Menu | BootLoader | — | **No seamless (reportado):** no hay espacio previo que bufferear; es el arranque. Queda loading screen + fade 0. |
| Menu → RingHub / Dome_Intro (Nueva partida / Continuar) | Menu.gd | — | **No seamless (reportado):** frontera UI→mundo, sin espacio físico previo. Queda fade del menú + loading. |
| RingHub ↔ MachineBay | RingHubLightState / MachineLevel:526 | umbral | Seamless: RingHubLightState ya declara `transition:"seamless"` explícito; MachineLevel debe hacer lo mismo (cambio reportado a src-51). El auto-upgrade los cubre igual mientras el AirlockManager esté armado. |
| Dome_Crio ↔ OdiseaExterior | AirlockZoneV2 | airlock | Seamless (referencia, migrada a `transition:"seamless"`): sin fade ni corte de BGM. |
| Dome → Hangar (#407) | HangarTransition | pozo/descenso | **Fade (conservado):** falta buffer de llegada equivalente y continuidad de cámara entre el pozo y el hangar; la migración a seamless quedó pendiente (review P1). Se mantiene la precarga temprana (descend_started) como optimización. |
| Tubos peatonales | TubeAirlock | tubo + IrisDoor | Seamless (migrado). |
| Airlock de la bahía (fallback) | BayAirlockTrigger | — | Seamless (migrado fallback; el camino primario va por RingHubLightState). |
| Portales genéricos (estilo airlock) | TransitionPortal | airlock | Seamless (migrado) cuando AirlockManager está presente; fade como fallback. |
| Cápsula de tránsito | TransitSystem | pod | Seamless cuando AirlockManager está presente (targets legacy no existen en el slice). |

## 5. API mínima que consume el productor

```gdscript
# Productor (dentro del buffer, p.ej. un trigger/al alcance del umbral):
var airlock_manager = get_node_or_null("/root/AirlockManager")
if airlock_manager != null and airlock_manager.has_method("notify_transition"):
    airlock_manager.notify_transition(destino_escena)

SceneManager.goto_scene(destino_escena, {
    "transition": "seamless",
    "target_spawn_id": id_spawn_destino,      # o state_data con airlock_relative_*
    "preserve_player_state": false,            # true si el destino tiene airlock espejo
    "state_data": { ... },                     # pose relativa al buffer
})
```

Valores garantizados por `SceneManager` en modo `seamless`:
- Sin `TransitionLayer` fade ni cartel de carga (aunque vengan `fade_out/fade_in/show_loading`).
- `_fade_audio_out` no se ejecuta; al llegar se refresca la BGM de zonas con `0s`.
- El swap usa add-before-free cuando el lift está armado.

## 6. Casos reportados como imposibles sin fade (evidencia)

- **Boot → Menu**: no existe escena anterior; un "seamless" sería un fade-in desde negro, que es exactamente lo que hace el boot (fade 0 + loading). No hay mundo que ocultar.
- **Menu → primera escena**: la frontera es UI (CanvasLayer) → mundo 3D; no hay espacio físico de transición ni cámara de mundo previa. El fade + pantalla de carga + warmup de shaders es el camino actual y no es reemplazable sin una escena de "despertar" que no está en el alcance (backlog).

## 7. Cambio requerido para MachineLevel.gd:526 (dueño: src-51)

Reemplazar el `goto_scene` de `return_to_ring_hub` por:

```gdscript
var airlock_manager = get_node_or_null("/root/AirlockManager")
var params := {
    "preserve_player_state": false,
    "ringhub_return_state": _ringhub_return_state.duplicate(true),
    "state_data": {"player_snapshot": _ringhub_return_state.get("player_snapshot", {})}
}
if airlock_manager != null and airlock_manager.has_method("notify_transition"):
    airlock_manager.notify_transition(target_scene)
    params["transition"] = "seamless"
scene_mgr.goto_scene(target_scene, params)
```

Nota: `RingHubLightState.enter_machine_bay` (hub→bahía) ya arma `notify_transition` y declara `"transition": "seamless"` en el payload.

**Deuda conocida (estado actual, 2026-11-14):** `MachineLevel.return_to_ring_hub`
(bahía→hub) NO usa seamless: conserva `wait_for_fade_out`, porque se dispara desde
`ReturnHubButton`, un pedestal abierto al final de la bahía (z=133) sin airlock físico
ni buffer de llegada; `AirlockManager` restaura la pose guardada del jugador en
RingHub, así que sin fade se vería de golpe el reemplazo bahía→hub y la
reubicación de la cámara. Para cerrar la deuda hace falta un **buffer de llegada
físico** (recorrido/puente entre la plataforma del pedestal y el spawn del hub, o un
airlock que recorra el pasaje real) antes de pasar este punto a seamless. La entrada
hub→bahía (`BayAirlockTrigger`) sí es seamless.
