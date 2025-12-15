# Especificación Técnica: Replay por Replicación de Inputs (Actualizada)

## 1\. Concepto Central: Simulación Determinista Unificada

**Principio:** El `PlayerController` nunca debe saber si está en modo *Live* o *Replay*. Debe ejecutar su bucle de física de forma **idéntica** en ambos modos. La única diferencia es la fuente de los datos de entrada:

| Modo | Fuente de **Inputs** | Fuente de **Delta Time** | Lógica Ejecutada |
| :--- | :--- | :--- | :--- |
| **Live** | Hardware (`Input.get_vector()`) | `Engine.get_physics_delta()` | **SIMULACIÓN COMPLETA** |
| **Replay** | Datos grabados (`inject_input()`) | **Delta grabado** (`recorded_delta`) | **SIMULACIÓN COMPLETA** |

**Eliminación del Problema:** Al ejecutar la *simulación completa* (`Gravity`, `Friction`, `move_and_slide`) en el modo Replay, se garantiza que las colisiones, pendientes y `snaps` del motor se manejen de forma nativa, solucionando la divergencia de estado.

## 2\. Abstracción de Inputs (`PlayerInput.gd`)

Esta clase es la clave del determinismo. Abstraerá el hardware y solo retornará un diccionario de inputs.

### 2.1. Implementación de `PlayerInput.gd`

```gdscript
# PlayerInput.gd
class_name PlayerInput

# NOTA: Debe ser un nodo hijo del PlayerController
export var is_replay_mode := false # Controlado por ReplayPlayback.gd
var _override_inputs: Dictionary = {} # Datos inyectados por el ReplayPlayback
var _previous_frame_inputs: Dictionary = {}

# MÉTODO CRUCIAL: Llamado por PlayerController para obtener TODOS los datos necesarios
func get_input_frame() -> Dictionary:
    if is_replay_mode:
        # Modo 1: Replay. Retorna el diccionario que inyectó el ReplayPlayback
        return _override_inputs.duplicate(true) 
    
    # Modo 2: Live. Lee el hardware real.
    var current_inputs = {
        # Usar get_vector para inputs analógicos
        "move_vec": Input.get_vector("left", "right", "forward", "backward"),
        
        # Usar just_pressed para acciones que solo suceden en un frame (Salto, Ataque, etc.)
        "jump": Input.is_action_just_pressed("jump"), 
        "attack1": Input.is_action_just_pressed("attack1"),
        
        # Usar is_action_pressed para acciones mantenidas (Sprint, Roll)
        "sprint": Input.is_action_pressed("sprint"),
        "roll": Input.is_action_pressed("roll"),
        
        # Usar el delta del mouse, si aplica
        "mouse_motion": Input.get_last_mouse_motion() 
    }
    _previous_frame_inputs = current_inputs.duplicate(true)
    return current_inputs

# MÉTODO LLAMADO POR REPLAYPLAYBACK.GD
func inject_input(frame_data: Dictionary):
    # Sobreescribe los inputs que se devolverán en el siguiente get_input_frame()
    _override_inputs = frame_data
```

## 3\. Arquitectura del Controlador (`PlayerController.gd`)

La lógica de movimiento debe ser **unificada**. El gran bloque `if not is_replaying:` debe eliminarse para que la física se ejecute siempre.

### 3.1. Corrección y Unificación del `_physics_process(delta)`

**Tu corrección clave debe ser la eliminación de las ramas de lógica de movimiento separadas:**

1.  **Eliminar las líneas de Inyección de Estado:** El bloque `else:` (`movement_this_frame = velocity`) debe ser eliminado, ya que contradice la especificación.
2.  **Mover el Procesamiento de Inputs:** Reemplazar las lecturas directas de `Input.` por llamadas a `player_input.get_input_frame()`.

<!-- end list -->

```gdscript
// PlayerController.gd (Refactorizado y Unificado)

// ... (variables de clase)
onready var player_input = $PlayerInput # Asumiendo que es un nodo hijo

func _physics_process(delta):
    # 1. ACTUALIZACIÓN DE TIEMPO (Siempre ejecuta)
    time_since_jump += delta
    time_since_input += delta
    # ... otras actualizaciones de tiempo

    # 2. OBTENER INPUTS DEL ABSTRACTION LAYER (Siempre ejecuta)
    # player_input sabe si debe dar hardware o datos grabados
    var input_data = player_input.get_input_frame()
    var input_vector := input_data.get("move_vec", Vector2.ZERO)
    var jump_pressed := input_data.get("jump", false)
    var is_sprinting := input_data.get("sprint", false)
    var mouse_motion := input_data.get("mouse_motion", Vector2.ZERO)
    # ... (obtener otros inputs: roll, attack, etc.)

    # 3. LÓGICA DE JUEGO / FÍSICA (Siempre ejecuta)
    
    # --- Gravedad y límites de velocidad (tu lógica actual) ---
    # La variable 'delta' que se usa aquí es el delta grabado si es replay!
    # ... (lógica de gravedad, clamp de velocidad vertical)

    # --- Procesamiento de Movimiento (Tank Turn, Rotation) ---
    rotation.y += input_vector.x * turn_speed * delta # <-- Usa el input_vector obtenido
    
    # --- Salto ---
    if jump_pressed and is_on_floor(): 
        # ... (toda la lógica de salto, heredando velocidad de plataforma, etc.)
        vertical_velocity = Vector3.UP * jump_force
        snap_enabled = false
        just_jumped = true
        time_since_jump = 0.0

    # --- Actualización de Componente de Movimiento y Velocidad Horizontal ---
    # ... (llama a movement_comp.process_input_vector y actualiza horizontal_velocity)
    
    # --- Combinación de Velocidades ---
    # ... (lógica de platform_velocity, airborne_inherited y combinación final)
    var combined_horizontal = horizontal_velocity + effective_platform_velocity
    var movement_this_frame = combined_horizontal + vertical_velocity
    
    # 4. EL PASO DE FÍSICA (Siempre ejecuta)
    var snap_vec := Vector3.ZERO
    if is_on_floor() and snap_enabled:
        snap_vec = Vector3.DOWN * snap_len
        
    velocity = move_and_slide_with_snap(movement_this_frame, snap_vec, Vector3.UP, false)
    
    # 5. POST-PROCESO
    # ... (actualización de horizontal_velocity = velocity - Vector3(0, velocity.y, 0))
    # ... (animaciones, sombra, etc.)
```

## 4\. Flujo de ReplayPlayback.gd (El Director de Orquesta)

El reproductor debe tomar el control del bucle de física.

### 4.1. Bucle de Reproducción

```gdscript
# ReplayPlayback.gd

# Configuración Inicial
func start_playback():
    # 1. Detener el bucle de física automático del motor para el jugador
    player.set_physics_process(false) 
    # 2. Configurar el input para que use datos inyectados
    player.input_component.is_replay_mode = true
    GameGlobals.is_replaying = true
    # 3. Posicionar el jugador en el estado inicial grabado
    # player.global_transform = initial_snapshot_data 
    
    set_process(true) # El ReplayPlayback usa su propio bucle _process o _physics_process

# El Bucle Manual de Stepping
func _process(delta):
    if not is_playing: return

    var frame_data = get_next_frame_from_json()
    if frame_data == null:
        stop_playback()
        return

    var recorded_delta = frame_data["d"] # El delta de tiempo en el que se grabó este frame
    var recorded_inputs = frame_data["i"] 

    # 1. INYECTAR INPUTS
    player.input_component.inject_input(recorded_inputs)

    # 2. FORZAR PASO DE FÍSICA con el DELTA GRABADO (¡CRUCIAL!)
    # Esto llama a PlayerController._physics_process(recorded_delta)
    player._physics_process(recorded_delta) 

    # 3. VERIFICACIÓN (Sync Check)
    if frame_data.has("snapshot"):
        var recorded_pos = frame_data["snapshot"]["pos"]
        var current_pos = player.global_transform.origin
        
        if recorded_pos.distance_to(current_pos) > SYNC_THRESHOLD:
            # Pausar y reportar la divergencia (¡Éxito del test!)
            print("ERROR: Desincronización en Frame %d. Divergencia: %f metros." % [frame_data["f"], recorded_pos.distance_to(current_pos)])
            stop_playback()
            return
            
    # Siguiente frame
    current_frame_index += 1
```

## 5\. Plan de Implementación (Paso a Paso Final)

| Paso | Módulo | Tarea Detallada | Verificación |
| :--- | :--- | :--- | :--- |
| **Paso 1** | `PlayerInput.gd` | Crea la clase y los métodos. Haz que `get_input_frame()` devuelva el diccionario del hardware. | Confirma que el `PlayerController` aún se mueve normalmente. |
| **Paso 2** | `PlayerController.gd` | Sustituye **toda** lectura de `Input.` con llamadas a `player_input.get_input_frame()["key"]`. **Elimina** el bloque `if not is_replaying/else`. | Confirma que el `PlayerController` sigue funcionando, pero ahora está *unificado* y sólo se comunica con `PlayerInput`. |
| **Paso 3** | `ReplayRecorder.gd` | Modifica para grabar únicamente `player.input_component.get_input_frame()` y `Engine.get_physics_delta()`. Añade el `snapshot` de `global_transform.origin` cada 60 frames. | El archivo JSON generado es pequeño y solo contiene *Inputs* y *Delta*. |
| **Paso 4** | `ReplayPlayback.gd` | Implementa la inicialización (desactivar `_physics_process` automático, `is_replay_mode = true`). Implementa el bucle manual que usa `inject_input()` y llama a `player._physics_process(recorded_delta)`. | El personaje se mueve exactamente igual que en la grabación (sin divergencias). |
| **Paso 5** | Debugging Visual | Implementa el "Fantasma de Referencia" que se renderiza en la posición de los `snapshots`. | Modifica un valor de gameplay (`jump_force`). Reproduce el replay y verifica que el personaje se separa del fantasma (divergencia exitosa). |