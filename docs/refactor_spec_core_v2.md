# Spec: Reconstrucción Paso a Paso (Core_V2)

## 1. Fase 1: Aislamiento y Estructura Base (Clean Slate)

El objetivo es crear un entorno donde nada de lo anterior interfiera.

* **Creación de `res://core_v2/**`: Carpeta raíz para todo el código nuevo.
* **Desactivación de Autoloads**: En la configuración del proyecto, desactivaremos temporalmente `InputState`, `PlayerManager` y `GameGlobals`. Si esto causa errores en el editor, los "mokearemos" (crear scripts vacíos) o simplemente los ignoraremos en nuestro código nuevo.
* **Clonación de Recursos Visuales**: Copiaremos `TestScene.tscn` y `Pilot.tscn` a `core_v2`. **Regla de oro:** Se les quitará el script original inmediatamente. Serán solo cáscaras visuales.

## 2. Fase 2: El Cerebro de Datos (`InputV2`)

Antes de mover al jugador, definiremos cómo se comunica la intención de movimiento.

* **`InputDataV2.gd`**: Objeto que contiene exclusivamente: `move_vec` (Vector2), `jump` (bool), `sprint` (bool), `mouse_delta` (Vector2).
* **`InputProviderV2.gd`**: El "Switch" maestro.
* En modo **LIVE**: Lee `Input` de Godot y devuelve un `InputDataV2`.
* En modo **REPLAY**: Lee un Array y devuelve el `InputDataV2` correspondiente al frame actual.



## 3. Fase 3: Movimiento Básico Determinista

Implementar el `PlayerControllerV2.gd` en la copia de Elias.

* **Inyección de Dependencia**: El controlador recibirá un `InputProviderV2`.
* **Física Manual**: El script tendrá un método `step(delta, input_data)` que ejecutará la lógica de `move_and_slide`.
* **Determinismo de Rotación**: La cámara y el cuerpo rotarán basándose exclusivamente en el `mouse_delta` guardado, no en eventos de mouse aleatorios del sistema.

## 4. Fase 4: Integración del Replay Nativo

No esperaremos al final; el replay se integrará mientras desarrollamos el movimiento.

* **Grabación en Caliente**: Cada vez que nos movamos en `LIVE`, se generará un buffer de inputs.
* **Validación Inmediata**: Botón de "Reproducir último intento" que resetee al jugador al inicio y use el buffer. Si el jugador no termina exactamente donde estaba, no pasamos a la siguiente fase.

## 5. Fase 5: Reconexión de Sistemas (Final)

Una vez que el núcleo físico sea perfecto:

* Reinstaurar sonidos y partículas.
* Reconectar la UI a los nuevos proveedores de datos.
* Migrar los cambios a la rama principal del proyecto.