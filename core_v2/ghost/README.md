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
