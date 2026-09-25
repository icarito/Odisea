# Handhelds lentos (tier LOW) — estado, alcance y hoja de ruta

Punto de entrada de FD-299 para la generación RK3326 (Anbernic RG351V y compañía: Mali-G31, 1 GB,
panel 640x480). Resume lo que está hecho, dónde vive cada ajuste y por dónde seguir.
La bitácora de mediciones, en orden cronológico, está en [plan.md](plan.md).
El diseño de los tiers está en [FD-299](../../features/FD-299_render_tier_lowend.md).

## Estado (2026-09-15, Anbernic RG351V)

| Escena, binario release | Antes | Ahora |
|---|---|---|
| Dome_Default | 17-19 fps | **28 fps** |
| Dome_Intro (entrando por el menú) | 4 fps, un tercio de la pantalla sin dibujar | **12 fps**, pantalla completa, 0 faults |
| RingHub_Level (replay de gameplay real, nivel completo) | ms_physics 70% del presupuesto de física, jugador caía al vacío a mitad de nivel (bug de tick-rate) | **ms_physics 47% del presupuesto** (mediana ~16 ms de 33.3 ms), nivel completo navegable, draw_calls 59-95. El desglose por sistema (ya lo vuelca `PerformanceMonitor`, solo había que mirarlo) apunta a `PlayerControllerV2.step()` como el ítem más caro (3.4 ms/tick, ~40% de todo el GDScript del tick) — no la geometría de colisión del piso (colliders a primitivas: mismo costo, se mantuvo solo por tamaño de escena). Ver [plan.md → RingHub_Level](plan.md#ringhub_level-replay-de-gameplay-real-física-domina-sobre-render-2026-09-20) |

Dos causas independientes, las dos resueltas:

1. **Pantalla cortada = driver del Mali**, no el juego. Con ROCKNIX 20250517 (`libmali` g13p0 sobre kbase
   r52p0) el driver pedía heaps del tiler de 368 MB en una zona de direcciones de GPU de 1 GB; el segundo no
   entraba y los jobs de fragmento abortaban (`DATA_INVALID_FAULT`, tiles sin dibujar). **ROCKNIX 20260901**
   (`libmali` g29p1, kbase r54p2) lo resuelve. Ver [plan.md → Driver del Mali](plan.md).
2. **Fps bajo = costo del tick de física**, no el render. Con ~18 ms de GDScript por tick a 60 Hz cada frame
   arrastraba 8 ticks (tope fijo del motor) y el juego corría al 54% del tiempo real.

> **RingHub / FD-314 (2026-09-22):** anillo de criopods del piso de despertar que no
> se dibujaba en el device, offset de 20 cm de los decorativos, y el contrato de
> colisión/replay. Detalle y herramientas en
> [`docs/engineering/RingHub_Criopods_Device_Notes.md`](../../engineering/RingHub_Criopods_Device_Notes.md).

## Qué se activa y dónde

Regla: **ningún ajuste de rendimiento toca desktop, Android, iOS, web ni handhelds rápidos.** Todo depende
de la detección de hardware lento o de la opción "low end" del menú.

**Tier LOW** = `GLES3VendorGate.is_low_tier()`: adapter Mali-G31 detectado **o** la opción "low end" de
Opciones activada.

| Ajuste | Dónde | Alcance |
|---|---|---|
| Física a 30 Hz (el paso del jugador se deriva de `Engine.iterations_per_second`) | `GLES3VendorGate.sync_physics_rate()` | tier LOW; se aplica también al cambiar la opción |
| Animator del piloto cada 5 ticks | `PlayerControllerV2._should_throttle_animator_for_profile()` | tier LOW |
| AnimationTree del piloto a 12 Hz | `PilotAnimatorV2._is_hyper_low_runtime()` | tier LOW |
| Pipes, Room3D, coolant cada 2 ticks; contexto de SuitOS y bus de sistemas cada 3 | `LowTierTickStride` | tier LOW |
| Presupuestos de luces, visuales y render scale adaptativo | `MobileLightBudget`, `AdaptiveVisualBudget`, `AdaptiveRenderScale` | móvil o tier LOW |
| Sombras apagadas y materiales simplificados | `GLES3VendorGate._low_tier_node()` | tier LOW |
| Dither de props apagado por defecto (el toggle de Opciones lo reactiva) | `PropDitherManager._resolve_occlusion_dither()` | tier LOW, salvo que el jugador lo haya tocado |
| Sombras falsas (blob/quad) apagadas por env | `GLES3VendorGate._sync_low_tier_env_hints()` | tier LOW |
| Control remoto: **host** desactivado (sin announcer/server/bridge ni `_process`); el **cliente** sigue vivo, el handheld puede usarse de mando | `RemoteControlManager._ready()` / `_is_low_tier()` | tier LOW |
| Animator del player a 12 Hz **solo en idle**; al moverse avanza al paso de física (30 Hz) | `PilotAnimatorV2._advance_animation_tree_if_manual()` | tier LOW (idle) |
| Auto-fit del shaft del ascensor cada 3 ticks | `ElevatorDoor` + `LowTierTickStride` | tier LOW |
| Lightmap manual (evita la colisión de unidad del lightmap nativo) | `GLES3VendorGate._sync_manual_lightmap()` + `IOSLightmapFallback` | solo Mali-G31 detectado |
| Perfil gráfico bajo desde el arranque (`ODISEA_GRAPHICS_PROFILE=low`, sin scatter, sin warmup) | `SessionManager._detect_weak_hardware_early()` | `ODISEA_EARLY_WEAK_HARDWARE=1` o huella ARM con ≤1 GB o SoC conocido |
| Ajustes de arranque de render (MSAA off, sombras 1024, vertex shading, 4 luces) | `portmaster/lowend.cfg`, que `Odisea.sh` copia a `override.cfg` | PortMaster en la generación RK3326 (device tree `rockchip,rk3326` o GPU Mali-G31) |
| Audio alineado al grafo de PipeWire: `mix_rate` 48000 (evita el resampleo 44100→48000), `output_latency` 40 ms y `mute_on_silence`/`mute_on_pause` (PR #63458) | `portmaster/lowend.cfg` (`[audio]`) | PortMaster en la generación RK3326 |
| Salida monofónica (downmix L/R, un solo parlante) | `AudioManager._apply_low_end_mono_audio()` (`AudioEffectStereoEnhance` con `pan_pullout=0` en el bus Master); reversible al apagar el perfil | tier LOW |
| Modo plano: albedo unshaded por superficie (`FlatFake.shader`), sin PBR ni lightmap | `ODISEA_UNSHADED=3` que exporta `Odisea.sh`; lo aplica `GLES3VendorGate._low_tier_node()` | PortMaster en la generación RK3326; `dev.sh` puede pisarlo (`0` apaga, `2` = unshaded con textura) |
| Inversión de ejes del stick | `GameControllerDB` (FRT abre `SDL_GameController`) | automático por GUID si el dispositivo está en el DB; *Invertir X/Y* en Opciones queda de fallback manual |

UI (vale para cualquier perfil con render scale < 100%): con stretch "viewport" la UI se dibuja a la misma
resolución que el 3D. Mientras Opciones o un widget en modo pantalla están abiertos, el render vuelve a
escala 1.0 (`SettingsManager.hold_full_resolution_ui`) y al cerrarlos vuelve la escala elegida.

## Bisección 2026-09-18 (replay determinista, release, RG351V)

Método: replay de `Dome_Intro` grabado en desktop (6415 frames) corrido en el dispositivo vía el hook
`odisea/dev.sh` (`--replay <json>`) más `ANNA_V2_BRIDGE` a un peer local; un reinicio por hipótesis y siempre
la misma ventana de ticks (100→400) para que el tramo del nivel no ensucie la comparación.

| Hipótesis | ticks/s | Δ | fps med |
|---|---|---|---|
| baseline | 2.60 | — | 3 |
| `render_scale=0.6` | 3.18 | +22% | 3 |
| `render_scale=0.5` y `render_resolution=640x480` | 3.17 | +22% | 3 |
| **dither de props off** | **4.12** | **+58%** | 4 |
| dither off + sombras falsas off | 4.43 | +70% | 5 |
| dither off + scans de interacción/zonas off | 4.32 | +66% | 4 |
| dither off + sombras + scans | 4.39 | +69% | 5 |

Lectura: bajar resolución no pasa de ~0.6 y de 0.6 a 0.5 no cambia nada ⇒ **no es fillrate**; ocultando toda
la geometría (`dc=0`, binario debug) el throughput se duplicaba, así que el render (draws/estado/driver) es
~50% del frame y el resto es por-nodo/script/física. El dither es la palanca grande y barata porque agrega
variantes de material (draw calls 144→128); las sombras falsas suman ~7%. Los scans de interacción/zonas
suman poco y se descartan por gameplay. Por eso el tier LOW ahora trae dither apagado por defecto y sombras
falsas apagadas; el toggle de Opciones sigue mandando.

Verificado en device con el nightly `0.4.0-nightly.632+5ac94eb`, misma ventana ticks 100→400:

| Estado | ticks/s | fps med | dc med |
|---|---|---|---|
| default tier LOW (dither off + sombras falsas off) | 3.99 (+53% vs 2.60) | 4 | 130 |
| dither forzado ON por el jugador (`prop_dither_user_set=true`) | 2.69 | 3 | 144.5 |

### CPU por tick: control remoto y auto-fit del ascensor (2026-09-18)

- **Control remoto apagado en tier LOW** (`RemoteControlManager`): no se instancian los 5 nodos
  (announcer/discovery/server/client/bridge) que corren `_process` por frame, ni hay host/UDP. En el
  handheld no tiene sentido (no lo va a manejar nadie desde otro equipo).
- **Auto-fit del shaft del ascensor cada 3 ticks** (`ElevatorDoor` + `LowTierTickStride`): el layout es
  estático y los setters ya fuerzan el recálculo al cambiar.

Medido con el replay (misma ventana), pck local deployado por SSH:

| | proc/tick | phys/tick | ticks/s |
|---|---|---|---|
| antes (nightly, referencias de hoy) | ~30 ms | ~35 ms | ~4.0 |
| después | 28 ms | 30 ms | 3.6-4.4 (ruido) |

Baja el costo por tick (~7 ms), pero **el fps no se mueve**: el frame del replay está limitado por
draws/driver, no por el tick de CPU. Sirve de headroom, no de fps; para fps hay que bajar draw calls /
materiales (carril de contenido/geometría).

### Animator: fluidez del player (2026-09-18)

El throttle de 12 Hz del `AnimationTree` en tier LOW hacía que el player caminara a 12 Hz (se veía
escalonado, muy por debajo del cap de 30 fps). Ahora el árbol avanza al **paso de física** (30 Hz en el
handheld, que es el cap de render: cada frame dibuja una pose nueva) y sólo baja a 12 Hz cuando el player
está **quieto y en piso**. Medido en el RG351V inyectando `move_forward` por `/eval`: idle `proc/phys`
2/5 ms y moviéndose 2/5 ms, sin cambio medible; la animación en movimiento queda fluida.

## Hoja de ruta: Dome_Intro de 12 a 20 fps

Presupuesto actual (release, 30 Hz): 12 fps son ~83 ms por frame. Con el juego en tiempo real hay ~2.5 ticks
por frame. Para 20 fps (50 ms) hay que bajar a ~1.5 ticks por frame y recortar el render.

Orden sugerido: primero lo medido y barato, después lo que requiere contenido.

1. **Tick del jugador (~6 ms de los ~16 ms de scripts por tick, binario debug).** Reparto: control 1.25 ms
   (escaneo de interacción y de zonas cinemáticas en cada tick, a propósito), move 1.6 ms, input y pre ~1 ms,
   post 0.9 ms. Espaciar en tier LOW el escaneo de interacción y de zonas cada 2 ticks, y medir
   `_rl_step_profile_*` antes y después.
2. **Resto del tick.** Pendientes medidos: HoloTerminalV2 0.95 ms (la oclusión de la pantalla del jugador
   puede ir con `LowTierTickStride`; el HUD pegado a la cámara no), Interactables 0.74, KinematicArm3D 0.62,
   SuspendedTerminalRig 0.46, OverTheShoulder 0.34. IceLevel 0.5 queda afuera porque su `step()`
   alimenta el replay.
3. **Materiales duplicados por el lightmap manual.** `IOSLightmapFallback` crea un `ShaderMaterial` por
   superficie (107): se rompe el agrupado por material y hay 47 cambios de shader por frame. Compartir un
   material entre superficies con el mismo lightmap y los mismos parámetros. Con g29p1 el lightmap nativo
   ya no sale magenta, pero es más lento (7.9 contra 10.7 fps) y el piso pierde el bake (L14), así que el
   camino es mejorar el manual.
4. **Geometría por frame (99 draws, 194k vértices en release).** Los mayores, medidos en índices:
   `WallLights/FixtureBatch_*` 96k cada uno (la malla "LOD" tiene ~2900 triángulos por lámpara: hace falta
   una LOD real de menos de 300), 10 válvulas de los risers de 14.8k cada una (decimar volante y cuerpo para
   tier LOW) y 10 anillos del coolant de ~13.7k. Es trabajo de contenido: decide Sebastián.
5. **Lado idle (~7 ms de scripts por frame).** LightPathV2 ×6, ElevatorDoor ×6, PathStudLayer ×3 y los 5
   nodos de RemoteControl hacen `_process` en cada frame. Medirlos apagándolos en vivo (como el tick) y
   espaciar los que sean visuales.
6. **Servidor de Box3D (~4 ms por tick).** Probar `physics/3d/box3d_substeps=1` solo en tier LOW. Cambia la
   sensación de las pilas de cajas y requiere un reinicio por medición.
7. **Sombras en el flujo real.** Verificar en el dispositivo que la DirectionalLight de Dome_Intro queda sin
   sombra al entrar por el menú. Arrancando directo en el nivel quedó con sombra, y apagarla dio +8%.

Palancas descartadas con medición (no repetir): AudioStreamPlayer3D, CPUParticles, Tween y Viewports
secundarios apagados; `shader_compilation_mode.mobile=0`; atlas de reflexiones en 0; `cma=128M`; subdividir el
piso; lightmap nativo.

## Probar el tier LOW en desktop (sin el handheld)

`Options -> Forzar modo low end` solo aplica el tier de **runtime** (`GLES3VendorGate`): física a
30 Hz, sombras apagadas, materiales aplanados, dither y sombras falsas off, control remoto off.
Los ajustes de `portmaster/lowend.cfg` (MSAA, FXAA, `framebuffer_allocation`, vertex shading,
lambert/blinn, atlas de sombras, límite de luces, reflexiones) y los de su bloque `[audio]`
(`mix_rate`, `output_latency`, `mute_on_silence`/`mute_on_pause`) los lee el motor **al arrancar** y
no se pueden cambiar en runtime, así que ese toggle por sí solo no reproduce el handheld.

Para bootear en desktop el mismo build que el handheld:

```bash
tools/launch_game.sh --lowend              # headful
tools/launch_game.sh --lowend --headless   # chequeo autónomo
```

`--lowend` instala `portmaster/lowend.cfg` como `override.cfg` del proyecto (quitando el sufijo
`.mobile`, que en desktop no aplica porque no existe el feature tag `mobile`) y exporta
`ODISEA_FORCE_LOW_TIER=1` para forzar el tier de runtime sin tocar `settings.cfg`. El
`override.cfg` se borra cuando termina el script (el motor solo lo lee al arrancar), y si había
uno previo se restaura.

Ojo: resolución y render scale son preferencias del jugador (`user://settings.cfg`), no del
override. El handheld corre a 640x480 con `render_scale=0.6`; para comparar 1:1 elegí esa
resolución y escala en Opciones.

## Cómo medir sin engañarse

- **Perfil del tick en vivo** (binario debug + `dev.sh` con `ENGINE` y el peer local):
  `get_node("/root/PerformanceMonitor").perfil_corrida_iniciar()`, esperar y `perfil_corrida_terminar()`.
  Para aislar un sistema, apagar su `_physics_process` en vivo y comparar "· scripts del tick".
- **Ticks por segundo de reloj**, no solo fps: `Engine.get_physics_frames()` en dos muestras.
- **Cobertura**: cámara propia y dos capturas con 0.4 m de desplazamiento. Un píxel que no cambia es un tile
  viejo; una captura suelta miente y la imagen puede quedar congelada.
- **Entrar a los niveles por el menú o por `SceneManager.goto_scene`**. Con `run/main_scene` directo el
  lightmap manual no llega a sincronizarse y el nivel sale magenta.
- **Un reinicio por cada cambio de estado GL** (§11.10). `/eval` no acepta `;` ni más de 512 caracteres.
- **En ROCKNIX**: `paste` sube texto a un pastebin; los core dumps del juego se acumulan en
  `/storage/.cache/cores` y pueden llenar `/storage`.
