# Ghost Replay & Sync Analyzer

## 1. Objetivo
Este sistema permite la grabación de una sesión de juego (inputs y estados de nodos) para su posterior reproducción simultánea con una sesión activa. Su propósito principal es facilitar la detección de "Desincronizaciones" (Desyncs) en el determinismo del engine `core_v2`.

## 2. Funcionamiento del "Ghost"
El Ghost es una representación visual no física (un "Dummy" verde/rojo) que sigue los datos grabados en un archivo `.ghost` (almacenado en `user://captures/`).

Durante la grabación, el sistema captura en cada frame (Tick):
*   Posición y Rotación del Jugador.
*   Un **Checksum de Estado** generado a partir de variables críticas (HP, Energía, Posición).

Durante la reproducción (`ghost_play`), el Ghost se mueve frame a frame siguiendo la grabación. El sistema compara en tiempo real el estado del jugador vivo contra el estado grabado.

## 3. Comandos de Consola (OYS-Shell)

El sistema se integra como un Actor OYS llamado `GhostManager`. Puedes invocar estos comandos desde la consola OYS o scripts `.oys`.

*   `CALL GhostManager ghost_record "nombre_grabacion"`
    *   Empieza a grabar la sesión actual. Guarda el archivo en `user://captures/nombre_grabacion.ghost` al finalizar.

*   `CALL GhostManager ghost_play "nombre_grabacion"`
    *   Carga la grabación y spawnea al Ghost.
    *   **Nota:** Debes asegurarte de que el nivel y la posición inicial del jugador sean los mismos que cuando se grabó para que la comparación sea válida.

*   `CALL GhostManager ghost_stop`
    *   Detiene la grabación o reproducción actual y elimina el Ghost.

*   `CALL GhostManager ghost_diff`
    *   Imprime en consola el estado actual de sincronización (distancia y checksum).
    *   Si hay desincronización, muestra qué variables difieren.

## 4. Visualización de Desincronización

*   **Green Trail / Dummy:** El fantasma está perfectamente sincronizado con el jugador (o la diferencia es despreciable).
*   **Red Flare / Dummy:** El fantasma y el jugador han divergido más de **0.5 unidades** de distancia o el checksum no coincide.
*   **Auto-Pause:** Si el sistema detecta que el **Checksum** del estado no coincide con el grabado, el juego se **pausará automáticamente** para permitir la inspección. Revisa la consola para ver qué variables causaron la divergencia.

## 5. Integración Técnica
El `GhostManager` se instancia dinámicamente en `SessionManager` (`core_v2/autoloads/SessionManager.gd`). No requiere configuración adicional en la escena.

## 6. Prueba Rápida Local

### 6.0 Ejemplo Integrado En Juego (TestSceneGhost)

Existe un ejemplo listo para usar dentro de la escena:
- Escena: `res://core_v2/levels/TestSceneGhost.tscn`
- Triggers:
  - `GhostRecordTrigger` -> `res://core_v2/scripts/ghost_record_start.oys`
  - `GhostLoopTrigger` -> `res://core_v2/scripts/ghost_stop_and_loop.oys`
  - Ambos con `trigger_once = false` (modo loop/reusable).

Cómo usarlo:
1. Abre `TestSceneGhost.tscn` y ejecuta la escena.
2. Entra a `GhostRecordTrigger` para iniciar grabación.
3. Muévete libremente y graba el recorrido que quieras.
4. Entra a `GhostLoopTrigger` para:
   - detener grabación
   - iniciar replay en loop continuo (`ghost_play_loop`)
5. Resultado esperado:
   - Se crea `user://captures/ghost_props_demo_loop.ghost`
   - Ves el dummy/cápsula ghost repitiendo el replay una y otra vez.

### 6.1 En escena (manual)
1. Ejecuta una escena jugable con piloto (por ejemplo `TestScene_v2.tscn`).
2. Abre la consola OYS y ejecuta:
   - `CALL GhostManager ghost_record "ghost_smoke"`
3. Muévete unos segundos con el personaje.
4. Detén la grabación:
   - `CALL GhostManager ghost_stop`
5. Vuelve al punto inicial (o recarga la escena para repetir condiciones).
6. Reproduce el ghost:
   - `CALL GhostManager ghost_play "ghost_smoke"`
7. Consulta estado de sincronización:
   - `CALL GhostManager ghost_diff`

### 6.2 Resultado esperado
- Se crea un archivo en `user://captures/ghost_smoke.ghost`.
- Aparece un dummy ghost durante `ghost_play`.
- El dummy permanece verde cuando está en sync.
- Si hay desync significativo, cambia a rojo y puede pausar para inspección.

### 6.3 Prueba desde script OYS
Puedes invocar los mismos comandos dentro de un `.oys`:

```oys
CALL GhostManager ghost_record "ghost_smoke"
WAIT 2s
CALL GhostManager ghost_stop
CALL GhostManager ghost_play "ghost_smoke"
WAIT 1s
CALL GhostManager ghost_diff
```

### 6.4 Smoke Test Automático (recomendado)

Para una validación rápida y visual del flujo completo:

```bash
./test_ghost.sh
```

Para correrlo headless:

```bash
./test_ghost.sh --headless
```

Este smoke script (`core_v2/scripts/test_ghost_smoke.oys`) ejecuta:
0. `ghost_record`
1. rotación visible de cámara con `LEFT 90` (validada por delta de yaw)
2. movimiento corto del jugador
3. `ghost_stop`
4. movimiento de separación del jugador
5. `ghost_play`
6. `ghost_stop`

Por defecto corre en `res://core_v2/levels/TestSceneGhost.tscn` para mejor visibilidad del ghost durante la validación visual.

### 6.5 Test OYS Full (Runner Debug)

Para ver el flujo completo con triggers (`record` -> `stop+loop`) en runner debug:

```bash
godot3-bin -s tests/debug_runner.gd --test-file core_v2/tests/test_ghost_trigger_loop.oys
```

O vía pytest raw-oys:

```bash
pytest tests/test_odisea_runner.py --odisea-runner raw-oys -k test_ghost_trigger_loop
```
