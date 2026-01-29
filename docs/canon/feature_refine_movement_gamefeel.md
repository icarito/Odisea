Especificación: Refinamiento de Gamefeel y Mecánicas (Core V2)

1. Salto Variable (Short Jump)

Para mejorar el control, el jugador debe poder controlar la altura del salto según cuánto tiempo presiona el botón.

Lógica: Si el jugador suelta el botón de salto (!input.jump) y la velocidad vertical es mayor a un umbral (ej. jump_velocity * 0.5), se debe aplicar una fuerza de frenado o recortar la velocidad vertical inmediatamente.

Determinismo: Esta comprobación debe ocurrir exclusivamente dentro del step(dt, input) del PlayerJumpV2.

2. Fricción Diferenciada (Air vs Ground)

El control en el aire debe sentirse "más pesado" o con menos capacidad de giro para evitar que el jugador sea demasiado ágil en el aire.

Nuevas Constantes:

movement_friction: Usada cuando is_on_floor().

air_friction: Usada cuando !is_on_floor() (típicamente un valor menor para permitir inercia, o mayor para restringir control).

Implementación: El PlayerMovementV2 debe seleccionar la fricción basada en el estado de colisión del frame anterior.

3. Curvas de Aceleración y Suavizado

Sustituir interpolaciones lineales simples por curvas de aceleración (Easings) para evitar el movimiento "robótico".

Plataformas: Usar SINE o CUBIC en los extremos del recorrido.

He colocado un directorio data/curves con las curvas de aceleración.

Input/Movimiento: Aplicar una curva de aceleración al wish_direction. El personaje no alcanza la velocidad máxima instantáneamente, sino que sigue una curva de aceleración.

Cámara: El seguimiento de la cámara debe usar un suavizado (SmoothDamp o Lerp determinista) que se ejecute en el step_camera(dt) para evitar jitter en el replay.

4. Re-añadir Tank Turn (Opcional por Zona)

El sistema debe permitir activar un modo de giro "Tank" (estilo Resident Evil/Tomb Raider clásico) donde:

El input lateral rota al personaje sobre su eje Y.

El input vertical lo mueve hacia adelante/atrás en su vector frontal (basis.z).

Estado: Debe ser un booleano use_tank_controls conmutable y capturable en el snapshot.

5. Agachado (Crouch)

Mecánica: Al presionar el input de agachado, se reduce la altura de la CollisionShape y se penaliza la max_speed (ej. 50%).

Visual: El PilotAnimatorV2 debe recibir la señal o el estado para cambiar a la animación de crouch_idle_loop o crouch_fwd_loop (el usuario puede editar el AnimationTree de acuerdo a tus instrucciones).

Importante: La reducción de la colisión debe hacerse hacia arriba para evitar que el jugador caiga a través del suelo o se quede atrapado en techos bajos.

6. Reglas de Oro para el Agente

Snapshots: Cualquier variable nueva de estado (ej. is_crouching, current_friction) DEBE incluirse en el snapshot.

Fixed Step: No se permite el uso de delta variable de _process. Todo refinamiento visual debe estar atado al FIXED_DT.

Fricción de Conveyors: La velocidad heredada de los conveyors debe sumarse al vector de movimiento final, no sustituirlo.
