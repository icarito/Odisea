# Odisea: El Arca Silenciosa — MVP Acto I


Odisea es un juego de plataformas 3D en tercera persona ambientado en una nave espacial, enfocado en el Acto I: “El Sepulcro Criogénico”. Controlas a Elías explorando la nave Odisea con mecánicas de movimiento, plataformas móviles y narrativa ambiental.

## Estructura del Proyecto (2026)

- **src/core/**: Todo el código fuente activo y refactorizado (componentes, sistemas, player_controller, UI, autoloads, simulación, utilidades, tests).
- **docs/canon/**: Especificaciones y features fundacionales implementados (OdysseyScript, interactuables, pushable box, gamefeel, sidescroller, test battery, test runner, etc).
- **docs/archived/**: Features descartados o legacy (ver notas en cada archivo).
- **AGENTS.md**: Contratos de desarrollo, determinismo y normas de trabajo.

## Contratos y Normas

Consulta **AGENTS.md** para reglas de determinismo, contratos de agentes, y normas de desarrollo (commits pequeños, tests con GdUnit3, todo en core, etc).

## Features Fundacionales (Canon)

Las siguientes features están implementadas y documentadas en `docs/canon/`:
- OdysseyScript DSL y replay determinista
- Sistema de interactuables y sensores
- PushableBox híbrido determinista
- Refinamiento de gamefeel y mecánicas
- Transición 2.5D sidescroller
- Test battery y runner de regresión determinista

## Descarga e Instalación

### Requisitos y Ejecución
1. Descarga Godot 3.6.x desde el sitio oficial: [godotengine.org/download](https://godotengine.org/download).
2. Abre el proyecto en Godot 3.6.x y ejecuta la escena principal: `res://scenes/Menu.tscn`.

### Testing determinista
Para validar determinismo y replays:
```sh
./runtest.sh -a ./core/tests/test_determinism.gd
```
Consulta los features canonizados en `docs/canon/` para ejemplos de scripts y tests.

### Validación de Props (Pipeline de Activos)

El proyecto cuenta con un pipeline automatizado para que agentes IA y desarrolladores validen visualmente los props sin abrir el editor gráfico.

1.  **Ejecución**:
    ```bash
    ./test_prop.sh --target="NombreDelProp" --base64
    ```
    *   Busca `NombreDelProp.tscn` en `core/props/`.
    *   Ejecuta Godot en modo headless usando `PropStage.tscn`.
    *   Corre el script de validación `prop_validator.oys` (Idle -> Interact -> Active -> Off).

2.  **Resultado**:
    *   Genera capturas de pantalla de cada estado en `test_output/props/`.
    *   Si se usa `--base64`, imprime las imágenes codificadas en la terminal.
    *   **Propósito**: El agente debe examinar estas imágenes para confirmar que la animación, posición y escalas son correctas. Si hay clipping o errores visuales, el agente debe corregir el `.tscn` o script y re-ejecutar el test.

### Validación en Editor (GUI)
Para depuración manual:
1. Abre `core/scenes/PropStage.tscn`.
2. Asigna tu prop a `Dev Prop Path` en el inspector del nodo raíz (`PropStage`).
3. Activa `Dev Take Screenshots` para correr la secuencia una vez.

## Sistema de Interactuables y Activación

La arquitectura de `core` separa estrictamente la **Lógica de Estado** (Determinista) de la **Representación Visual** (Interpolada), fundamental para el sistema de Replays.

### Contrato `InteractableBase`
Todo objeto interactuable (Puertas, Palancas, Válvulas) debe heredar de `InteractableBase` o sus hijos.

*   **Estado Lógico**: `is_active` (bool). Definido por la simulación.
*   **Estado Visual**: `anim_progress` (float 0.0 - 1.0). Avanza en `_physics_process` mediante `step(dt)`.
*   **Determinismo**: `_update_visuals()` es una función pura de `anim_progress`. Nunca usar `Tween` o `AnimationPlayer` para lógica de juego; usar solo para efectos visuales cosméticos no-físicos.

### Primitivas Disponibles
No reinventar la rueda. Usar estas clases base cuando sea posible:

*   **`DualSlidingObject`**: Para puertas o compuertas.
    *   Exporta `mesh_a_path`, `mesh_b_path`.
    *   Vectores de deslizamiento independientes `slide_vector_a/b`.
    *   Ejemplo: `HeavyBlastDoor`.
*   **`RotatingObject`**: Para válvulas, palancas o puertas giratorias.
    *   Exporta `rotation_axis` y `rotation_amount`.
    *   Usa interpolación angular determinista.
    *   Ejemplo: `VentilationTurbine` (si aplica).

### Conectividad y Controladores
Los sistemas complejos se construyen componiendo nodos simples:

1.  **Controladores (e.g., `AirlockController`)**:
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
4.  **Iterar**: El agente analiza la imagen. ¿La puerta traspasa el suelo? Ajustar. ¿Se abre al revés? Ajustar vector. Repetir hasta éxito.
