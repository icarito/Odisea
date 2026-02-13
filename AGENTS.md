# AGENTS.md — Guía de Desarrollo (Odisea)


> [!WARNING] INVERTED COORDINATE SYSTEM
> This project uses an unorthodox coordinate system where **+Z is BACK** (Camera Direction) and **-Z is FORWARD**.
> Consequently, spawning an object "in front" of the player often involves placing it at **positive Z** (e.g. `(0, 1, 3)`) as seen in `test_push_integration.oys`.
> **ALWAYS verify direction visually** or via small test steps. Do not assume standard conventions apply universally without checking.

## ⚠️ ANTES DE ENTREGAR CUALQUIER CAMBIO

**Ejecutar los tests para verificar que no se rompió nada:**

```shell
./runtest.sh -a ./core_v2/tests/
```

Si algún test falla, corregirlo antes de considerar el trabajo terminado.

###  Optimización: Correr Tests Selectivamente

**Si sabes qué test es relevante para tu cambio, córrelo primero para agilizar:**

```shell
# Correr un archivo de test específico
./runtest.sh -a ./core_v2/tests/test_mi_feature.gd

# Correr solo los tests de un archivo
./runtest.sh -a ./core_v2/tests/test_player_controller_v2.gd
```

**Solo corre TODOS los tests al final**, antes de entregar el trabajo completo:

```shell
./runtest.sh -a ./core_v2/tests/
```

### 📋 Leer el Output de los Tests

**El output siempre se guarda en `./reports/gdunit_runner.log`**

Si el terminal no muestra el output (problema común con agentes IA), leer el archivo:

```shell
# Ver las últimas 100 líneas del log
cat ./reports/gdunit_runner.log | tail -100

# O buscar solo el resumen (PASSED/FAILED/errores)
grep -E "(PASSED|FAILED|ERROR|Total|Exit code|SCRIPT ERROR)" ./reports/gdunit_runner.log
```

### Ejecutar un Test OYS Específico

```shell
./runtest.sh --oys test_salto_vertical
```

## Setup Testing Environment

To execute tests, you need to have Godot 3 installed (binary named `godot3` or set `GODOT_BIN` env var).

Example installation (Ubuntu):
```bash
sudo apt-get update && sudo apt-get install -y godot3
```

## Notas sobre Godot
- **IMPORTANTE:** Usar siempre el alias `godot3-bin` para ejecutar Godot 3.6. El comando `godot` puede apuntar a Godot 4, lo que causará errores de sintaxis (ej. `yield` vs `await`).
- "Index 1 is out of bounds (count = 1)" aparece _siempre_ al arrancar, pero no es un problema con nuestro código.
- Ternario: `a if cond else b`.
- Declarar con type hints: `var x: int = 0`.
- No usar `nil` donde se esperan tipos concretos (bool, Vector2); usar valores por defecto.
- Usar `_nombre` para miembros de uso interno (no hay private/protected).

## Objetivo (MVP Acto I)
- Juego 3D en Godot 3.6 (GLES2): 3ª persona, plataformas móviles/conveyors

## Contratos Críticos

### PlayerController — Movimiento y Plataformas

El `PlayerControllerV2` usa **Transform-Delta Tracking** para seguir plataformas móviles (inspirado en [Terrestrial Characters](https://github.com/Trokara)):

1. **Tracking de Plataformas**: Almacena `_platform_collider` y `_platform_last_transform`. Cada frame calcula dónde *estaría* el jugador si siguiera perfectamente la plataforma:
   ```gdscript
   var old_local = platform_last_transform.affine_inverse().xform(player_pos)
   var new_global = platform.global_transform.xform(old_local)
   var delta = new_global - player_pos
   player.global_transform.origin += delta
   ```
2. **Herencia de Velocidad**: Al saltar o salir de una plataforma, hereda `_platform_velocity` para conservar momentum.
3. **Alineación a Pendientes**: `PlayerMovementV2.align_to_floor()` rota el vector de movimiento para que siga el plano del suelo, evitando drift lateral en rampas.
4. **Resistencia en Pendientes**: Ralentiza el movimiento cuesta arriba según el ángulo (configurable via `slope_resistance_factor`).
5. **Stair-Stepping**: `_try_step_up()` permite subir escalones automáticamente hasta `step_height` (default 0.4m).

#### API Legacy: `set_external_velocity()`

Se conserva `set_external_velocity(v: Vector3)` para:
- **Conveyors**: Aplican fuerza continua sobre el jugador (necesitan `external_source_is_static = false`).
- **Efectos especiales**: Knockback, viento, explosiones, etc.
- **Objetos legacy**: Compatibilidad con sistemas antiguos.

> **Nota**: Las plataformas móviles (`MovingPlatformV2`) ya NO necesitan llamar `set_external_velocity()` para el jugador. El tracking por transform lo hace automáticamente. Sin embargo, deben seguir llamándolo para otros cuerpos (cajas, NPCs) que no tengan tracking propio.

- **Conveyor**: Aplicar velocidad a cuerpos en su área, usando `set_external_velocity()` para el jugador con `external_source_is_static = false`.
- **Signals**: Las señales no deben usarse para lógica que afecte el estado físico (posición, velocidad). Su uso debe limitarse a efectos no deterministas (sonido, animaciones, UI). Por ejemplo, `PilotAnimatorV2` puede escuchar señales para disparar animaciones, pero no debe alterar el `state` del `PlayerController`.

## Normas de Trabajo
- Commits pequeños y enfocados. Validar cambios en `TestScene_v2.tscn`.
- Documentar `export var` en el Inspector.
- Usar GdUnit3 para tests.
- **Todo el código nuevo o refactorizado debe ir en `src/core_v2`**.

## Contrato de Replay Determinístico

Para garantizar replays determinísticos, todo agente sincronizado debe:

1.  Pertenecer al grupo `replay_sync`.
2.  Implementar `restore_snapshot(data: Dictionary)`.
3.  Ejecutar toda la lógica de movimiento/simulación en `_physics_process(delta)`. **Nunca en `_process(delta)`**.
4.  Consumir input a través de `InputProviderV2` (jugador) o basarse solo en estado interno (NPCs).

### Ejecución de Tests de Determinismo

```shell
# Ejecutar el test de determinismo para core_v2
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```

Este comando utiliza el script `runtest.sh` para lanzar Godot en modo headless y ejecutar la suite de tests especificada. Si el `drift` (desviación) entre la posición final del replay y la esperada supera un umbral mínimo, el test fallará, indicando una ruptura en el determinismo.

## Nota para Agentes: Verificación de Assets

Al trabajar con Props o Elementos Interactuables, sigue este procedimiento recurrente:
1.  **Ejecución**: Usa `./test_prop.sh --target="NombreDelProp" --base64` para capturar los estados visuales.
2.  **Reporte**: Muestra los resultados (imágenes/base64) al usuario inmediatamente después de cualquier cambio en el asset.
3.  **Iteración**: No consideres un asset terminado hasta que el usuario confirme que las capturas de pantalla son correctas.