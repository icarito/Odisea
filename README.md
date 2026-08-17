# Odisea: El Arca Silenciosa — MVP Acto I


Odisea es un juego de plataformas 3D en tercera persona ambientado en una nave espacial, enfocado en el Acto I: “El Sepulcro Criogénico”. Controlas a Elías explorando la nave Odisea con mecánicas de movimiento, plataformas móviles y narrativa ambiental.

## Estructura del Proyecto (2026)

- **src/core_v2/**: Todo el código fuente activo y refactorizado (componentes, sistemas, player_controller, UI, autoloads, simulación, utilidades, tests).
- **docs/canon/**: Especificaciones y features fundacionales implementados (OdysseyScript, interactuables, pushable box, gamefeel, sidescroller, test battery, test runner, etc).
- **docs/archived/**: Features descartados o legacy (ver notas en cada archivo).
- **AGENTS.md**: Contratos de desarrollo, determinismo y normas de trabajo.

## Contratos y Normas

Consulta **AGENTS.md** para reglas de determinismo, contratos de agentes, y normas de desarrollo (commits pequeños, tests con GdUnit3, todo en core_v2, etc).

## Operación

- **Sistema de Actualización Segura (FD-228)**: guía operativa del mecanismo de updates (palancas de release, deberes del operador, rotación de clave, promoción a estable) en [core_v2/update/README.md](core_v2/update/README.md).

## Features Fundacionales (Canon)

Las siguientes features están implementadas y documentadas en `docs/canon/`:
- OdysseyScript DSL y replay determinista
- Sistema de interactuables y sensores
- PushableBox híbrido determinista
- Refinamiento de gamefeel y mecánicas
- Transición 2.5D sidescroller
- Test battery y runner de regresión determinista

## Los cuatro sistemas de la nave

Criocoolant, plasma, atmósfera y energía auxiliar: los órganos industriales de la Odisea.
Cada uno avisa antes de dañar, y se libera reordenándolo en vez de destruyéndolo.

**→ [Guía de funcionamiento de los cuatro sistemas](docs/systems/four-ship-systems.md)** —
qué hace cada uno, cómo está armado, cuál es la lógica de sus interruptores y dónde tocar
para mejorarlo. Banco de pruebas: `core_v2/tests/TestShipSystems.tscn` (F6).

Diseño: [FD-255](docs/features/FD-255_systems_master.md) y sus hijos FD-256 a FD-259. La lógica de flujo del coolant (grafo OCLS + puente visual) vive en [FD-264](docs/features/FD-264_coolant_flow_graph.md) — en diseño.

## Integración de Agentes (ANNA V1 — DEPRECATED)

La integración de agente externo A.N.N.A (bridge TCP + interfaz de observación/acción) está **deprecada** y preservada solo para compatibilidad con scripts RL legacy. Para telemetría y debugging moderno, consultar **AGENTS.md §9** (Telemetry).

Documentación legacy:
- `docs/features/archive/FD-008_anna_agent.md`
- `core_v2/anna/README.md`

## Descarga e Instalación

### Requisitos y Ejecución
1. Descarga Godot 3.6.x desde el sitio oficial: [godotengine.org/download](https://godotengine.org/download).
2. Abre el proyecto en Godot 3.6.x y ejecuta la escena principal: `res://scenes/Menu.tscn`.

### Testing determinista
Para validar determinismo y replays:
```sh
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```
Consulta los features canonizados en `docs/canon/` para ejemplos de scripts y tests.

### Validación de Props (Pipeline de Activos)

El proyecto cuenta con un pipeline automatizado para que agentes IA y desarrolladores validen visualmente los props sin abrir el editor gráfico.

1.  **Ejecución**:
    ```bash
    ./test_prop.sh --target="NombreDelProp" --base64
    ```
    *   Busca `NombreDelProp.tscn` en `core_v2/props/`.
    *   Ejecuta Godot en modo headless usando `PropStage.tscn`.
    *   Corre el script de validación `prop_validator.oys` (Idle -> Interact -> Active -> Off).

2.  **Resultado**:
    *   Genera capturas de pantalla de cada estado en `test_output/props/`.
    *   Si se usa `--base64`, imprime las imágenes codificadas en la terminal.
    *   **Propósito**: El agente debe examinar estas imágenes para confirmar que la animación, posición y escalas son correctas. Si hay clipping o errores visuales, el agente debe corregir el `.tscn` o script y re-ejecutar el test.

### Validación en Editor (GUI)
Para depuración manual:
1. Abre `core_v2/scenes/PropStage.tscn`.
2. Asigna tu prop a `Dev Prop Path` en el inspector del nodo raíz (`PropStage`).
3. Activa `Dev Take Screenshots` para correr la secuencia una vez.

## Sistema de Interactuables y Activación

La arquitectura de `core_v2` separa estrictamente la **Lógica de Estado** (Determinista) de la **Representación Visual** (Interpolada), fundamental para el sistema de Replays.

### Contrato `InteractableBaseV2`
Todo objeto interactuable (Puertas, Palancas, Válvulas) debe heredar de `InteractableBaseV2` o sus hijos.

*   **Estado Lógico**: `is_active` (bool). Definido por la simulación.
*   **Estado Visual**: `anim_progress` (float 0.0 - 1.0). Avanza en `_physics_process` mediante `step(dt)`.
*   **Determinismo**: `_update_visuals()` es una función pura de `anim_progress`. Nunca usar `Tween` o `AnimationPlayer` para lógica de juego; usar solo para efectos visuales cosméticos no-físicos.

### Primitivas Disponibles
No reinventar la rueda. Usar estas clases base cuando sea posible:

*   **`DualSlidingObjectV2`**: Para puertas o compuertas.
    *   Exporta `mesh_a_path`, `mesh_b_path`.
    *   Vectores de deslizamiento independientes `slide_vector_a/b`.
    *   Ejemplo: `HeavyBlastDoor`.
*   **`RotatingObjectV2`**: Para válvulas, palancas o puertas giratorias.
    *   Exporta `rotation_axis` y `rotation_amount`.
    *   Usa interpolación angular determinista.
    *   Ejemplo: `VentilationTurbine` (si aplica).
*   **`HoloTerminalV2`**: Para terminales holográficas e interfaces interactivas.
    *   Exporta `slide_height` (distancia de despliegue), `slide_speed`, `screen_resolution`.
    *   Animación slide+scale del `ScreenContainer` controlada por `anim_progress`.
    *   Incluye CinematicSetup (CameraZone + FocusedRig) para interacción en primera persona.
    *   Ejemplos: `HoloTerminalV2`, `TableTerminal`, `WallTerminal`, `HelmetHUD`.

### Conectividad y Controladores
Los sistemas complejos se construyen componiendo nodos simples:

1.  **Controladores (e.g., `AirlockControllerV2`)**:
    *   No heredan necesariamente de `Interactable`.
    *   Orquestan múltiples interactuables (`outer_door`, `inner_door`).
    *   Se conectan vía `NodePath` exports (`outer_door_path`).
    *   Llaman explícitamente a `set_active(bool)` en sus hijos.
2.  **Señales**:
    *   Interactables emiten `interaction_started`, `interaction_completed`, `activated`, `deactivated`.
    *   Útil para efectos de sonido, partículas o UI (`Observer` pattern).

## Flujo de Trabajo con Agentes (Nota)

Para implementar un nuevo prop:
1.  **Definir**: Crear escena heredando de la Primitiva adecuada.
2.  **Configurar**: Ajustar meshes y vectores en el Inspector.
3.  **Validar**: Ejecutar `./test_prop.sh ... --base64`.
    *   Si existe `NombreDelProp.oys` junto al `.tscn`, en `core_v2/scripts/`, o en `core_v2/tests/`, se usa automáticamente en lugar del validador genérico.
    *   Los scripts personalizados pueden usar `SPAWN scene="..."` para posicionar cámaras o helpers (ej: `CameraClose.tscn`).
4.  **Iterar**: El agente analiza la imagen. ¿La puerta traspasa el suelo? Ajustar. ¿Se abre al revés? Ajustar vector. Repetir hasta éxito.
