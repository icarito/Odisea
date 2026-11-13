# Odisea NPC-holograma — bitácora de sesión, 2026-11-13

## Objetivo

Hacer aparecer a Odisea como NPC-holograma cuando habla. V1 minimal: SOLO aparición/
desaparición (sin movimiento). El cuerpo de Odisea es el actor `Programmer`; se
reutiliza únicamente el visual (`res://models/Programmer.glb`) con el material
holográfico existente (`ProgrammerHoloShader`/`ProgrammerHoloMaterial`), sin instanciar
el `PlayerControllerV2`.

## Diseño implementado

- **`core_v2/autoloads/OdiseaHologramV2.gd`** (nuevo, autoload `OdiseaHologramV2`):
  - Instancia `Programmer.glb` con el material holográfico (duplicado, para manejar el
    fade sin afectar otros usuarios del material). Desactiva sombras y colisión (no hay
    cuerpos físicos: es puramente decorativo).
  - API: `show_holo(duration)`, `hide_holo()`, `is_holo_active()`. (No puede llamarse
    `show()`/`hide()`: chocan con los métodos heredados de `Spatial`.)
  - Fade-in/fade-out determinista por ticks de `_physics_process` (nada de `randf`/
    `randomize`; el uniform `fade_alpha` del shader escala albedo/emisión/alpha).
  - Scene-agnóstico: se coloca delante de la cámara activa, anclado al piso (el origen
    del mesh está en los pies; `anchor_height=0` por defecto). Fallback junto al jugador
    si no hay cámara; punto fijo si no hay jugador.
  - Hook observer: escucha la señal `said(text, duration)` de los nodos `MachineLevel`
    (se conecta cuando la raíz entra al árbol vía `child_entered_tree` + escaneo).
- **`core_v2/actors/OdiseaHologramV2.tscn`** (nuevo): escena mínima con el script.
- **`core_v2/visual/ProgrammerHoloShader.shader`**: se agregó `uniform float fade_alpha
  = 1.0` y se aplicó a `ALBEDO`, `EMISSION` y `ALPHA`. Default 1.0: no altera los usos
  existentes (p. ej. el actor `Programmer_v2`).
- **`core_v2/props/machines/MachineLevel.gd`** (hook mínimo):
  - `signal said(text, duration)` (declaración; requerida para poder `connect`).
  - En `say()`: una línea `emit_signal("said", text, effective_duration)`. No se tocó
    nada más del archivo (ni señalética ni layout).
- **`project.godot`**: se registró el autoload `OdiseaHologramV2` (una línea), siguiendo
  el precedente del repo de registrar managers nuevos con commit dedicado. Es la única
  desviación de "no tocar project.godot": sin ese registro el autoload no existe. Si se
  prefiere, es una línea revertible.
- **`core_v2/tests/test_odisea_hologram.gd`** (nuevo): cubre construcción del visual,
  fade-in hasta alpha 1, ocultamiento tras la duración, fade-out inmediato, conexión
  observer a `MachineLevel` (`said`) y ausencia de jugador.
  - Nota de harness: los `yield(get_tree(), "physics_frame")` deben ir inline en el cuerpo
    del test; dentro de helpers no suspenden y los tests quedan "congelados" (falsa
    alarma de que `_physics_process` no corría).

## Reportes

- **`ao report --checkpoint`** tras milestone de implementación + tests verdes.
- **`ao report --done`** al completar integración/PR (con artifact de capturas y PR).

## Verificación

```bash
# Suite nueva del holograma
/usr/bin/pytest tests/test_odisea_runner.py -q -k test_gd__core_v2_tests_test_odisea_hologram_gd
# -> 1 suite, 6 casos PASSED

# Regresión focalizada de bahía/máquinas
/usr/bin/pytest tests/test_odisea_runner.py -q -k "test_machine_level or test_machine_bay or test_machine_launch or test_machine_sign_scale"
# -> 6 suites PASSED (124.89s)

# Manifests de imports
python3 scripts/check_tracked_imports.py
# -> 952 manifests correctos
```

### Capturas (960x540, DISPLAY :0, Intel Iris Xe)

Driver temporal `core_v2/tests/capture_holo_driver.{gd,tscn}` (eliminado al terminar):
carga `MachineBay`, elimina los triggers de voz del layout, deshabilita
`hardware_input_enabled` y dispara un `say` de 25 s controlado. Captura con
`Camera.get_texture()`.

| Archivo | Estado del holograma (motor) | Observación visual |
|---|---|---|
| `odisea_holo_during1.png` | active=true, visible=true, alpha=1 | Holo en frame (proyección sx=453, sy=330); escena brillante, cian presente en centro (center_cyan≈6.3k) |
| `odisea_holo_during2.png` | activ=true, visible=true, alpha=1 | Idem |
| `odisea_holo_after.png` | active=false, alpha=0 | Tras desaparecer; el cian central baja (≈3.4k, resto es iluminación del entorno) |

Paths: `/home/icarito/.ao/data/artifacts/src-8/odisea_holo_during{1,2}.png`,
`odisea_holo_after.png`.

## Pendientes / atención humana

1. **Aprobar composición/posición**: el holograma aparece delante de la cámara a 2.4 m,
   anclado al piso. ¿Se siente bien la distancia/altura? ¿Debería mirar al jugador
   (rotación en Y) en lugar de quedar con la orientación del rig?
2. **Reimportar `Programmer.glb`**: pedido por Sebastián ("cambio en configuración de
   normales"). El binario `.glb` y los parámetros `.import` están idénticos a
   `10da94ab`; `fadf685a` sólo regeneró el `.scn`. Se forzará reimport cuando no haya
   otro import smoke en curso y se revalidará el `.scn`.
3. **Build con Mono**: pedido por Sebastián: una vez integrada la NPC, evaluar un build
   del motor con Mono para usar el modelo de movimiento entrenado antes. Fuera del
   alcance v1; dejar anotado para el orquestador.
4. **Holo "momentáneo"**: el fade usa ticks de física; en escenas pesadas los ticks van
   más lento que el reloj de pared (la desaparición puede tardar un poco más en tiempo
   real). Es aceptable y determinista; se puede revisar si molesta.

## Riesgos / decisiones

- El autoload se registra en `project.godot` (desviación explícita, revertible).
- MachineLevel queda con una señal nueva `said`; no toca señalética ni el resto del
  flujo. Coordinar con el worker de bahía visual (src-6) al mergear MachineLevel.gd.
- `Programmer.glb` es compartido con el jugador: cualquier restauración de versión
  anterior cambia también al actor jugable (fuera del alcance de esta tarea).
