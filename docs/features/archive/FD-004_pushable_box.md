Especificación: PushableBoxV2 (Objeto Híbrido Determinista)

1. Objetivo

Crear un objeto con comportamiento físico dual: un modo "Dinámico" para caídas y rotaciones realistas (6DoF), y un modo "Cinemático" para reposo, apilamiento y transporte determinista. Este sistema permite realismo visual sin comprometer la integridad del replay.

2. Clase Base y Configuración

Nodo: RigidBody (Configurado para alternar modos).

Grupo: replay_sync.

Configuración Inicial: mode = MODE_RIGID. El control de step(dt) manejará el cambio a MODE_KINEMATIC.

3. Lógica de Estados (Híbrido)

A. Estado Dinámico (Caída/Caos)

Cuando el objeto es golpeado con fuerza o cae de una plataforma:

Se comporta como un RigidBody estándar de Godot.

Permite rotaciones en los 3 ejes y colisiones complejas.

Determinismo: Para minimizar el drift, se fuerza el sleeping = false y se registra cada frame en el replay.

B. Estado Cinemático (Asentamiento)

Cuando la velocidad lineal y angular caen por debajo de un umbral (threshold) durante N frames:

Snap de Rotación: Si la rotación está cerca de los 90°, se hace un "snap" automático a los ejes globales para asegurar que sea apilable.

Cambio de Modo: Se cambia a MODE_KINEMATIC.

Drift Correction: Se redondea la posición a 4 decimales para eliminar inconsistencias de coma flotante del motor de física.

4. Integración de Simulación step(dt)

En lugar de dejarlo 100% en manos del motor, el step supervisa el estado:

Monitoreo: Si está en modo Dinámico, verifica si linear_velocity.length() < 0.1.

Transición: Si se cumple el reposo, guarda la posición actual como la nueva "posición de anclaje" determinista.

Interacción: Si el jugador toca el objeto en modo Cinemático, el objeto "despierta" volviendo a modo Dinámico para reaccionar al impacto.

5. Contrato de Replay (Snapshots)

El snapshot debe capturar el modo actual para saber cómo restaurar la física.

func get_snapshot() -> Dictionary:
    return {
        "pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
        "rot": [global_transform.basis.get_euler().x, global_transform.basis.get_euler().y, global_transform.basis.get_euler().z],
        "vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
        "ang": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
        "mode": mode # Captura si es RIGID o KINEMATIC
    }

func restore_snapshot(data: Dictionary):
