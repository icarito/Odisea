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

Dos causas independientes, las dos resueltas:

1. **Pantalla cortada = driver del Mali**, no el juego. Con ROCKNIX 20250517 (`libmali` g13p0 sobre kbase
   r52p0) el driver pedía heaps del tiler de 368 MB en una zona de direcciones de GPU de 1 GB; el segundo no
   entraba y los jobs de fragmento abortaban (`DATA_INVALID_FAULT`, tiles sin dibujar). **ROCKNIX 20260901**
   (`libmali` g29p1, kbase r54p2) lo resuelve. Ver [plan.md → Driver del Mali](plan.md).
2. **Fps bajo = costo del tick de física**, no el render. Con ~18 ms de GDScript por tick a 60 Hz cada frame
   arrastraba 8 ticks (tope fijo del motor) y el juego corría al 54% del tiempo real.

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
| Lightmap manual (evita la colisión de unidad del lightmap nativo) | `GLES3VendorGate._sync_manual_lightmap()` + `IOSLightmapFallback` | solo Mali-G31 detectado |
| Perfil gráfico bajo desde el arranque (`ODISEA_GRAPHICS_PROFILE=low`, sin scatter, sin warmup) | `SessionManager._detect_weak_hardware_early()` | `ODISEA_EARLY_WEAK_HARDWARE=1` o huella ARM con ≤1 GB o SoC conocido |
| Ajustes de arranque de render (MSAA off, sombras 1024, vertex shading, 4 luces) | `portmaster/lowend.cfg`, que `Odisea.sh` copia a `override.cfg` | PortMaster en la generación RK3326 (device tree `rockchip,rk3326` o GPU Mali-G31) |
| Inversión de ejes del stick (`ODISEA_DEVICE=anbernic`) | `InputProviderV2` | todos los dispositivos PortMaster (es input, no rendimiento) |

UI (vale para cualquier perfil con render scale < 100%): con stretch "viewport" la UI se dibuja a la misma
resolución que el 3D. Mientras Opciones o un widget en modo pantalla están abiertos, el render vuelve a
escala 1.0 (`SettingsManager.hold_full_resolution_ui`) y al cerrarlos vuelve la escala elegida.

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
