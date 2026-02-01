Especificación Técnica: Sistema Cinemático (Gameplay & Tráiler)

Este documento define la arquitectura para el manejo de cámaras cinematográficas integradas en el gameplay y las herramientas de exportación para la creación de material promocional (tráiler).

1. El Rig Cinemático (CinematicRig)

Un CinematicRig es un nodo de cámara especializado que puede ser estático o estar animado.

Componentes:

Camera: El nodo visual principal.

AnimationPlayer: (Opcional) Para movimientos de cámara, cambios de FOV o transiciones de color.

Identificación: Cada rig posee un rig_id único para ser invocado por triggers o scripts OYS.

Comportamiento: Al activarse, se convierte en la cámara actual del Viewport y dispara su animación asignada.

2. Zonas de Cámara (CinematicCameraZone)

Para forzar el uso de cámaras específicas durante el gameplay sin quitarle el control al jugador, se utiliza el nodo CinematicCameraZone.

Funcionalidad de la Zona:

Trigger Geométrico: Un Area que detecta la entrada del jugador.

Activación de Rig: Al entrar, busca el CinematicRig por su ID y le otorga el control visual.

Persistencia: Al salir de la zona, la cámara vuelve al PlayerCamera estándar.

Reconfiguración de Controles (Contrato de Input):

Al entrar en una zona, el jugador debe ajustar su cálculo de movimiento según el ControlMode especificado en la zona:

Modo de Control

Descripción

FREE

El movimiento sigue siendo relativo a la cámara del jugador (estándar).

SIDESCROLL

El movimiento se restringe a un plano (X o Z) independientemente del ángulo.

LOCKED_VIEW

"Arriba" en el stick siempre es "Hacia el fondo" de la cámara cinemática.

FIXED_AXIS

El movimiento ignora la rotación de la cámara y usa ejes globales.

Nota Crítica: El controlador del jugador debe consultar el basis de la cámara actual para transformar el vector de entrada (input_vector), asegurando que el control no se vuelva "invertido" desde ángulos inusuales.

3. Sistema de Grabación (Tráiler Tooling)

Para la generación de frames de alta calidad destinados a tráilers, el sistema incluye un FrameRecorder.

Exportación de Frames: Si export_on_start está activo, el juego corre a un framerate fijo (ej. 60 FPS) y exporta cada frame como un archivo .png numerado en la carpeta de usuario.

Sincronización: El tiempo del motor (Engine.iterations_per_second) se bloquea para evitar saltos de frames durante la escritura a disco.

4. Integración con OYS (Odyssey Script)

El sistema cinemático es controlable mediante comandos de script:

CINEMATIC_START "ID_CAMARA": Activa un rig específico.

CINEMATIC_STOP: Devuelve el control a la cámara de gameplay.

RECORD_START: Inicia la captura de frames a disco.

5. Criterios de Éxito

La transición entre la cámara de gameplay y la cinemática es fluida (uso de interpolación si es necesario).

El jugador puede navegar por el entorno bajo una cámara cinemática sin que los controles se sientan erráticos.

El sistema de grabación produce una secuencia de imágenes sin pérdida de frames ni jittering de física.