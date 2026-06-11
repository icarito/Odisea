# Optimización de OdiseaExterior

Hallazgos y sugerencias de optimización para la escena OdiseaExterior, con foco en el build HTML5/WebGL.

## Hallazgos (Telemetría Bridge)
- **42.4% de frames < 30 FPS**: Rendimiento deficiente crítico en sesiones largas.
- **FPS avg 34.7**: Indica que incluso en picos, el rendimiento está cerca del límite.
- **Fugas de rendimiento**: Sesiones largas mantienen 9-28 FPS, sugiriendo sobrecarga acumulativa en el procesado de `_process` o `_physics_process` de sistemas que gestionan LOD/Streaming.

## Análisis de Escena (`OdiseaExterior.tscn` & `.gd`)

### 1. Sistema de LOD y Streaming (FD-041)
- El sistema utiliza `TerraceSegmentManager` y `PlateContentStream` para gestionar la visibilidad de los domos.
- En HTML5, `dome_lod_camera_update_enabled` está desactivado por defecto para ahorrar CPU, pero esto puede causar que se rendericen objetos fuera de frustum si no hay un buen culling.
- El presupuesto de CPU para `_tick_dome_assignment_cache_build` es de 4ms por frame. En Web, esto es significativo si el main thread ya está saturado.

### 2. Luces Dinámicas
- Existen múltiples `OmniLight` (OmniLight, OmniLight4, OmniLight5) con `omni_range = 500`.
- Aunque no tienen sombras activas en el .tscn (`omni_shadow_mode = 0`), el cálculo de iluminación para 500 unidades en GLES2 es costoso, especialmente si afectan a geometrías complejas como las espirales de la terraza.

### 3. FauxSkydome
- `FauxSkydomeParallaxShell` está presente. Los shaders de paralaje de múltiples capas son costosos en WebGL.

## Sugerencias de Optimización

### A. Luces
- **Desactivar Luces Omni en Web**: Sustituir por iluminación horneada (Baked Lightmaps) o simplificar a una única `DirectionalLight` para el sol/espacio.
- **Reducir Rango**: Si son necesarias, reducir el `omni_range` de 500 a algo más razonable (100-150) y usar atenuación más agresiva.

### B. Geometría e Instancing
- **MultiMesh para Scaffold**: Asegurarse de que todos los elementos repetitivos de la estructura (scaffold) usen `MultiMeshInstance` en lugar de nodos `MeshInstance` individuales.
- **LOD de Materiales**: En GLES2, reducir el número de materiales únicos. Agrupar texturas en atlas para reducir Draw Calls.

### C. Ajustes de Script (`OdiseaExterior.gd`)
- **Reducir `dome_lod_overlay_max_instances`**: Actualmente en 32. Para Web, bajar a 16 o 20 puede reducir significativamente las llamadas de dibujo de MultiMesh LOD.
- **Throttling de Actualizaciones**: Incrementar `exterior_collision_update_interval` y `exterior_target_plate_query_interval` en builds Web para liberar el Main Thread.

### D. Post-Process
- Desactivar Glow y Ambient Occlusion explícitamente en la escena para builds HTML5 si no se está haciendo ya vía `SessionManager`.

## Acciones Aplicadas
1. Se ha reducido `dome_lod_overlay_max_instances` de 32 a 24 en `OdiseaExterior.tscn` como medida inmediata.
2. Se recomienda revisar el shader de `FauxSkydome` para simplificarlo en la rama de producción.
