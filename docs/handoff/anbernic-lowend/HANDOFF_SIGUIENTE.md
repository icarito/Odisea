# Handoff para el próximo agente — Anbernic RG351V: 3D a medias (FD-299)

**Fecha:** 2026-09-14, fin de turno de Kilo. **Estado del código:** rama `fd-299-anbernic-lowend`,
commits `8d42fd57` (probe), `94b1ac78` (mediciones), `ed57f99c` (H2+H3 y feature tag).
**Fuente de verdad de resultados:** tabla "Resultados" y "Notas de medición" de `plan.md` (mismo directorio).
**Lee primero:** `AGENTS.md` §11.9/§11.10, este archivo completo, `plan.md`.

## Problema abierto

El 3D solo se pinta en un bloque escalonado alineado a tiles de Mali (16/32 px) de la pantalla.
El cielo/estrellas rasteriza a pantalla completa; la geometría opaca solo sobrevive en algunos
tiles. No depende de: MSAA (H1), HDR/framebuffer ni tamaños de sombra (H2+H3), ni del shader
de la geometría (UNSHADED live → mismo recorte, resto magenta). La cobertura es estable por
escena (Dome_Intro ~30% fijo; Dome_Prologue intermitente 85-100%), y Sebastián reporta que a
veces se repinta al mover el joystick. fps 2 en Dome_Intro, dc 194, vtx 321k.

## Lo verificado (no repetir)

1. **FRT expone el feature tag `mobile`** (frt_godot.cc:171: X11, FRT, mobile, etc). "Android" NO.
2. El motor registra GLOBAL_DEFS taggeadas `.mobile` (visual_server.cpp:2678-2711: shadow sizes
   2048, filter_mode 0, force_vertex_shading true, lambert/blinn true, etc).
3. `ProjectSettings::_set/_get` (project_settings.cpp:199-237): un tag activo registra
   `feature_overrides[plain] = tagged` y `_get(plain)` resuelve al tagged **para siempre**.
   → `override.cfg` con claves planas queda sombreado. **Usar sufijo `.mobile`** (verificado por eval).
4. Config efectiva hoy en el Anbernic (override.cfg `.mobile` instalado): framebuffer=3,
   shadow atlas 1024, directional 1024, filter PCF0, msaa 0, fxaa off. La pre-exploración del
   plan (4096/PCF13) era falsa.
5. H1 y H2+H3 no arreglan la cobertura. La memoria GPU bajó solo ~8k págs. El recorte no es
   (solo) presión de memoria: CMA 64 MB casi agotada, pero reducir buffers no mueve el patrón.
6. Las ráfagas de faults `DATA_INVALID_FAULT 0x58/0x5b` son episódicas (carga en release, idle
   tardío en debug); entre ráfagas hay 0 faults con cobertura igual de rota.
7. El screenshot del motor (ANNA, readback del viewport) muestra el mismo recorte que `grim`
   → es render-side, no presentación.
8. Relanzar el juego **solo vía ES por Sebastián** (SSH no muestra la ventana). `pkill` por SSH sí.

## Estado del dispositivo (`root@angel.local`, port en `/storage/roms/ports/odisea/`)

- Binario activo: `godot.box3d.frt.arm64.debug` v0.2.7 vía `dev.sh` (ENGINE override).
  Release original respaldado como `odisea.frt.aarch64.release` (restaurar al cerrar la tarea:
  `cp odisea.frt.aarch64.release odisea.frt.aarch64` y borrar `dev.sh`).
- `dev.sh`: `export ANNA_V2_BRIDGE=192.168.18.6:4999`, `ANNA_V2_ALWAYS_STREAM=1`, ENGINE=debug.
- `override.cfg` (con sufijo `.mobile`): msaa 0, fxaa false, framebuffer_allocation.mobile=3,
  shadow_atlas/size.mobile=1024, directional_shadow/size.mobile=1024, shadows/filter_mode.mobile=0.
- Control en vivo: peer local en la desktop (`tools/ensure_peer.sh`), `curl localhost:4999/eval?expr=...`
  (una expresión por llamada; asignaciones NO compilan — usar `obj.set('prop', valor)` con valor
  numérico; los enum como `Viewport.DEBUG_DRAW_UNSHADED` no resuelven, usar 1).
- Capturas: `tools/anbernic_probe.sh <etiqueta> [seg]` (grim + métricas + TSV en
  `/tmp/odisea_probe/results.tsv`). El ring de dmesg rota: el probe cuenta por timestamp kernel.

## Pruebas pendientes, en orden (una por reinicio limpio; Sebastián relanza)

1. **H6 — Panfrost (mayor probabilidad de resolver de raíz).** ROCKNIX trae switcher propio:
   `/usr/bin/gpudriver` con setting `gpu.driver` (default `libmali`). Kernel tiene
   `panfrost.ko` (modinfo ok) y Mesa está instalada (`/usr/lib/dri/panfrost_dri.so`,
   `libEGL_mesa.so`, `/usr/share/glvnd/egl_vendor.d/50_mesa.json`). Panfrost soporta G31
   (Bifrost v7) con GLES 3.1 — suficiente para el GLES3 del juego.
   Pasos: `set_setting gpu.driver panfrost` (o el flujo oficial de ROCKNIX/Opciones) + **reboot
   del sistema completo** (no solo el juego; Sebastián). Verificar `GL_RENDERER` en log.txt y
   dmesg (`panfrost` en vez de `mali ff400000.gpu`). Mismo protocolo de medición. Revertir:
   `gpu.driver libmali` + reboot. Riesgo: otros emuladores corren con panfrost hasta revertir.
2. **H5b — apagar el lightmap manual del gate.** El gate activa `ODISEA_MANUAL_LIGHTMAP=1` en
   Mali-G31 (GLES3VendorGate.gd:60). Por eval justo tras el boot (en menú, antes de cargar el
   nivel): `OS.set_environment('ODISEA_MANUAL_LIGHTMAP','')` y
   `get_node('/root/GLES3VendorGate').set('_gated_active',false)`. Cargar Dome_Intro y medir.
   Si completa la cobertura → el camino manual (unidad de textura extra) es el disparador.
3. **H5a limpio — debug_draw UNSHADED desde boot.** El test live (mid-carga) no cambió el
   recorte, pero confunde variantes de shader compiladas antes del toggle. Repetir seteando
   `get_tree().root.set('debug_draw',1)` en menú y cargando Dome_Intro después.
4. **H7 — resolución de render.** `settings.cfg` tiene `render_scale=0.6` (384×288). El borde
   del recorte en espacio de render cae cerca de potencias de 2 (256). Probar render_scale=1.0
   (o `ODISEA_DEVICE` sin el perfil low-end del launcher) a ver si el patrón cambia. Antes,
   grep de dónde se aplica render_scale (SessionManager/AdaptiveRenderScale) para saber qué
   tocar sin reinicios a ciegas.
5. **Si nada: trazas.** `WAYLAND_DEBUG=1` sobre el juego (breve, ~2 s, filtrar eglSwapBuffers/
   wl_surface_damage) y comparar con un nivel sano. Opciones del blob: buscar env knobs del
   libmali-bifrost-g31-g13p0 (`strings` del .so por `MALI_`).

## Reglas duras (sin cambios)

Una hipótesis por reinicio; nunca cambios de estado GL en vivo como test (§11.10). Los
relanzamientos los hace Sebastián desde ES. No editar `[rendering]` de project.godot. Commits
chicos en `fd-299-anbernic-lowend`, español neutro. No push a main.

## Pistas para la causa raíz (por si sirven al próximo)

- El cielo completa a pantalla completa y la geometría no → el aborto es del job de fragmento
  de la geometría opaca por tiles, no del framebuffer completo.
- El patrón es DETERMINÍSTICO por escena (Dome_Intro siempre ~30%), no aleatorio.
- Con UNSHADED el shader trivial no arregla nada → no es complejidad de fragment shader.
- Sospechosos restantes: (a) bug del blob libmali-bifrost-g31-g13p0 con Transaction
  Elimination / mapeo parcial de tiles (por eso Panfrost es el test decisivo); (b) el camino
  de lightmap manual del gate (unidad de textura extra en cada material); (c) interacción
  FRT/EGL/wayland con el buffer de 384×288 escalado.
