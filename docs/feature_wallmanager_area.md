Especificación Técnica: Sistema de Oclusión Cónica y Zonas de Cámara

1. Objetivo General

Implementar un sistema híbrido de cámara para Odisea que resuelva la visibilidad en interiores estrechos sin los saltos bruscos del SpringArm.

Modo Estándar (Exteriores): La cámara usa colisiones físicas (SpringArm) para evitar muros.

Modo Oclusión (Interiores/Pasillos): Al entrar en una OcclusionArea, la cámara ignora las colisiones (atraviesa muros) pero activa un Shader de Recorte Cónico que hace transparentes los obstáculos solo si están entre la cámara y el jugador.

2. Componentes del Sistema

A. OcclusionZoneV2.gd (Nuevo Nodo)

Un área que define zonas donde la geometría debe volverse transparente.

Herencia: Area.

Señales: Al detectar al Player, notifica al WallOcclusionManager y al PlayerSpringCam.

Propiedades Exportables:

camera_distance_override: (Float, opcional) Fuerza una distancia fija de cámara dentro de la zona.

cone_radius: (Float) Radio del agujero de visión en el shader.

B. WallOcclusionManager.gd (Autoload o Componente Global)

Encargado de pasar los datos uniformes globales a los shaders de los muros.

Responsabilidad: En _process, actualiza los uniformes:

global_player_pos

global_camera_pos

occlusion_active (bool/float)

C. PlayerSpringCam.gd (Modificación)

Necesita un método para cambiar de modo.

Método: set_occlusion_mode(enabled: bool, fixed_length: float = -1)

Si enabled == true: Desactiva la máscara de colisión del SpringArm (para que atraviese paredes). Si hay fixed_length, ajusta la longitud del brazo suavemente.

Si enabled == false: Restaura la máscara de colisión original.

3. Lógica del Shader (El "Cono de Visión")

El shader debe aplicarse a los materiales de las paredes (en Qodot, esto significa editar el shader base de los materiales del mapa o usar VisualServer.global_shader_parameter si usas Godot 4, pero para Godot 3.6 usaremos un enfoque de material compartido o iteración).

Algoritmo de Transparencia Selectiva:
Para cada píxel (fragmento) del muro:

Vector Vista: Calcular el vector desde la Cámara hasta el Jugador (V = Player - Cam).

Vector Fragmento: Calcular el vector desde la Cámara hasta el Muro (F = Frag - Cam).

Proyección: Proyectar F sobre V para saber "qué tan lejos" está el muro a lo largo de la línea de visión.

t = dot(F, normalize(V))

Condición de Profundidad (CRÍTICA):

Si t > length(V): El muro está detrás del jugador. NO transparentar.

Si t < 0: El muro está detrás de la cámara. Ignorar.

Condición de Radio (El Cono):

Calcular la distancia perpendicular desde el fragmento al rayo central (dist_to_axis).

Si dist_to_axis < cone_radius: Aplicar transparencia (Dithering discard).

Código GLSL de Referencia (Para el Agente)

uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 1.5;
uniform float is_active = 0.0; // 0.0 o 1.0

void fragment() {
    // ... lógica de textura existente ...

    if (is_active > 0.5) {
        vec3 cam_to_player = player_pos - camera_pos;
        float dist_cam_player = length(cam_to_player);
        vec3 dir_cam_player = normalize(cam_to_player);
        
        // Posición del píxel actual en el mundo (requiere varying en vertex)
        vec3 cam_to_frag = world_pos - camera_pos;
        
        // Proyección escalar sobre la línea de visión
        float t = dot(cam_to_frag, dir_cam_player);
        
        // Solo afectamos objetos que estén ANTES del jugador (con un pequeño margen)
        if (t > 0.0 && t < (dist_cam_player - 0.2)) {
            // Distancia radial al eje de visiónEspecificación Técnica: Sistema de Oclusión Cónica y Zonas de Cámara
1. Objetivo General

Implementar un sistema híbrido de cámara para Odisea que resuelva la visibilidad en interiores estrechos sin los saltos bruscos del SpringArm.

    Modo Estándar (Exteriores): La cámara usa colisiones físicas (SpringArm) para evitar muros.

    Modo Oclusión (Interiores/Pasillos): Al entrar en una OcclusionArea, la cámara ignora las colisiones (atraviesa muros) pero activa un Shader de Recorte Cónico que hace transparentes los obstáculos solo si están entre la cámara y el jugador.

2. Componentes del Sistema
A. OcclusionZoneV2.gd (Nuevo Nodo)

Un área que define zonas donde la geometría debe volverse transparente.

    Herencia: Area.

    Señales: Al detectar al Player, notifica al WallOcclusionManager y al PlayerSpringCam.

    Propiedades Exportables:

        camera_distance_override: (Float, opcional) Fuerza una distancia fija de cámara dentro de la zona.

        cone_radius: (Float) Radio del agujero de visión en el shader.

B. WallOcclusionManager.gd (Autoload o Componente Global)

Encargado de pasar los datos uniformes globales a los shaders de los muros.

    Responsabilidad: En _process, actualiza los uniformes:

        global_player_pos

        global_camera_pos

        occlusion_active (bool/float)

C. PlayerSpringCam.gd (Modificación)

Necesita un método para cambiar de modo.

    Método: set_occlusion_mode(enabled: bool, fixed_length: float = -1)

        Si enabled == true: Desactiva la máscara de colisión del SpringArm (para que atraviese paredes). Si hay fixed_length, ajusta la longitud del brazo suavemente.

        Si enabled == false: Restaura la máscara de colisión original.

3. Lógica del Shader (El "Cono de Visión")

El shader debe aplicarse a los materiales de las paredes (en Qodot, esto significa editar el shader base de los materiales del mapa o usar VisualServer.global_shader_parameter si usas Godot 4, pero para Godot 3.6 usaremos un enfoque de material compartido o iteración).

Algoritmo de Transparencia Selectiva: Para cada píxel (fragmento) del muro:

    Vector Vista: Calcular el vector desde la Cámara hasta el Jugador (V = Player - Cam).

    Vector Fragmento: Calcular el vector desde la Cámara hasta el Muro (F = Frag - Cam).

    Proyección: Proyectar F sobre V para saber "qué tan lejos" está el muro a lo largo de la línea de visión.

        t = dot(F, normalize(V))

    Condición de Profundidad (CRÍTICA):

        Si t > length(V): El muro está detrás del jugador. NO transparentar.

        Si t < 0: El muro está detrás de la cámara. Ignorar.

    Condición de Radio (El Cono):

        Calcular la distancia perpendicular desde el fragmento al rayo central (dist_to_axis).

        Si dist_to_axis < cone_radius: Aplicar transparencia (Dithering discard).

Código GLSL de Referencia (Para el Agente)

uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 1.5;
uniform float is_active = 0.0; // 0.0 o 1.0

void fragment() {
    // ... lógica de textura existente ...

    if (is_active > 0.5) {
        vec3 cam_to_player = player_pos - camera_pos;
        float dist_cam_player = length(cam_to_player);
        vec3 dir_cam_player = normalize(cam_to_player);
        
        // Posición del píxel actual en el mundo (requiere varying en vertex)
        vec3 cam_to_frag = world_pos - camera_pos;
        
        // Proyección escalar sobre la línea de visión
        float t = dot(cam_to_frag, dir_cam_player);
        
        // Solo afectamos objetos que estén ANTES del jugador (con un pequeño margen)
        if (t > 0.0 && t < (dist_cam_player - 0.2)) {
            // Distancia radial al eje de visión
            vec3 projection = camera_pos + dir_cam_player * t;
            float dist_radial = distance(world_pos, projection);
            
            if (dist_radial < hole_radius) {
                // Usar dithering para evitar problemas de alpha sorting
                if (dither_pattern(SCREEN_UV) < 0.9) {
                    discard;
                }
            }
        }
    }
}

4. Plan de Implementación para el Agente

    Paso 1 (Shader): Crea un Wall.shader que incluya la lógica matemática descrita arriba. Implementa una función dither_pattern 4x4.

    Paso 2 (Manager): Crea el script WallManager.gd. Debe buscar todos los MeshInstance que sean hijos del mapa (QodotMap) y, si comparten el material, actualizar sus parámetros player_pos y camera_pos en cada frame.

    Paso 3 (Area): Implementa OcclusionArea.gd. Al entrar el cuerpo Pilot_v2:

        Llamar a PlayerSpringCam.set_occlusion_mode(true).

        Activar el shader globalmente (o en los materiales gestionados).

    Paso 4 (Cámara): Modificar PlayerSpringCam.gd para guardar su máscara de colisión original en _ready() y permitir alternarla a 0 (sin colisión) cuando se solicite.

5. Criterios de Éxito

    Al entrar en la zona, la cámara atraviesa la pared en lugar de acercarse al personaje.

    Se forma un agujero circular en la pared que permite ver al personaje.

    El suelo bajo los pies del personaje y la pared detrás de él permanecen sólidos (opacos).
            vec3 projection = camera_pos + dir_cam_player * t;
            float dist_radial = distance(world_pos, projection);
            
            if (dist_radial < hole_radius) {
                // Usar dithering para evitar problemas de alpha sorting
                if (dither_pattern(SCREEN_UV) < 0.9) {
                    discard;
                }
            }
        }
    }
}


4. Plan de Implementación para el Agente

Paso 1 (Shader): Crea un Wall.shader que incluya la lógica matemática descrita arriba. Implementa una función dither_pattern 4x4.

Paso 2 (Manager): Crea el script WallManager.gd. Debe buscar todos los MeshInstance que sean hijos del mapa (QodotMap) y, si comparten el material, actualizar sus parámetros player_pos y camera_pos en cada frame.

Paso 3 (Area): Implementa OcclusionArea.gd. Al entrar el cuerpo Pilot_v2:

Llamar a PlayerSpringCam.set_occlusion_mode(true).

Activar el shader globalmente (o en los materiales gestionados).

Paso 4 (Cámara): Modificar PlayerSpringCam.gd para guardar su máscara de colisión original en _ready() y permitir alternarla a 0 (sin colisión) cuando se solicite.

5. Criterios de Éxito

Al entrar en la zona, la cámara atraviesa la pared en lugar de acercarse al personaje.

Se forma un agujero circular en la pared que permite ver al personaje.

El suelo bajo los pies del personaje y la pared detrás de él permanecen sólidos (opacos).