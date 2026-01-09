# Spec: Reconstrucción Paso a Paso (Core_V2)

## 1. Fase 1: Aislamiento y Estructura Base (Clean Slate) — Completada

El objetivo es crear un entorno donde nada de lo anterior interfiera.

* **Creación de `res://core_v2/**`: Hecha.
* **Limpieza de Autoloads**: Autoloads legacy removidos (AudioSystem, GameGlobals, GameConfig, PlayerManager, InputState, FixedPoint, TouchCounter, UIManager).
* **Clonación de Recursos Visuales**: `TestScene_v2.tscn` y `Pilot_v2.tscn` en `core_v2` sin scripts legacy.

## 2. Fase 2: El Cerebro de Datos (`InputV2`) — Completada

Antes de mover al jugador, definiremos cómo se comunica la intención de movimiento.

* **`InputDataV2.gd`**: Implementado.
* **`InputProviderV2.gd`**: Implementado (LIVE/REPLAY).



## 3. Fase 3: Movimiento Básico Determinista — Completada

Implementar el `PlayerControllerV2.gd` en la copia de Elias.

* **Inyección de Dependencia**: `PlayerControllerV2.gd` consume `InputProviderV2`.
* **Simulación**: Lógica en `_physics_process(delta)` con determinismo.
* **Determinismo de Rotación**: Basado en `mouse_delta`.

## 4. Fase 4: Integración del Replay Nativo — Completada (mínimo viable)
* Grabación y reproducción integradas en `core_v2/tests/test_determinism_v2.gd`.
* Drift validado < 0.000009.

No esperaremos al final; el replay se integrará mientras desarrollamos el movimiento.

* **Grabación en Caliente**: Cada vez que nos movamos en `LIVE`, se generará un buffer de inputs.
* **Validación Inmediata**: Botón de "Reproducir último intento" que resetee al jugador al inicio y use el buffer. Si el jugador no termina exactamente donde estaba, no pasamos a la siguiente fase.

## 5. Fase 5: Reconexión de Sistemas (Final)

Una vez que el núcleo físico sea perfecto:

* Reinstaurar sonidos y partículas.
* Reconectar la UI a los nuevos proveedores de datos.
* Migrar los cambios a la rama principal del proyecto.