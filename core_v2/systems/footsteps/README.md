# Dynamic Footstep System (Odisea)

Sistema de pasos dinámico para Godot 3.6, inspirado en el sistema de Cogito.

## Componentes

### FootstepProfile (`footstep_profile.gd`)
Recurso que contiene una lista de sonidos de pasos y configuración de randomización.

**Propiedades:**
- `streams: Array` - Lista de AudioStream (sonidos de paso)
- `random_pitch_min/max: float` - Rango de variación de tono
- `random_volume_db_min/max: float` - Rango de variación de volumen

**Perfiles incluidos:**
- `footstep_profile_default.tres` - Metal/Tile (sonidos Step_Tile)
- `footstep_profile_dirt.tres` - Tierra
- `footstep_profile_stone.tres` - Piedra
- `footstep_profile_wood.tres` - Madera
- `footstep_profile_grass.tres` - Pasto

### FootstepDetector (`footstep_detector.gd`)
Componente que detecta la superficie bajo el jugador y reproduce el sonido apropiado. Se coloca como hijo del nodo visual del personaje.

**Propiedades:**
- `generic_fallback_profile: Resource` - Perfil de sonido por defecto
- `footstep_material_library: Resource` - Librería de materiales (opcional)

**Métodos:**
- `play_footstep()` - Detecta superficie y reproduce sonido de paso
- `play_landing()` - Reproduce sonido de aterrizaje

### FootstepSurface (`footstep_surface.gd`)
Nodo que se adjunta a objetos para definir su sonido de paso.

**Propiedades:**
- `footstep_profile: AudioStream` - Sonido de paso para esta superficie

### FootstepMaterialLibrary (`footstep_material_library.gd`)
Recurso que mapea materiales a perfiles de sonido.

**Propiedades:**
- `footstep_material_library: Array` - Array de FootstepMaterialProfile

### FootstepMaterialProfile (`footstep_material_profile.gd`)
Relación entre un material y un perfil de sonido.

**Propiedades:**
- `material: Material` - Material a detectar
- `footstep_profile: AudioStream` - Sonido asociado

## Uso

### 1. Configuración básica (Fallback)
El `FootstepDetector` ya incluido en `Pilot_v2.tscn` tiene asignado el perfil default. Solo necesitas agregar el nodo a tu escena:

```gdscript
# El detector ya está configurado en Pilot_v2.tscn
# El animator llama automáticamente a footstep_detector.play_footstep()
```

### 2. Asignar sonido a un objeto específico
Agrega un nodo `FootstepSurface` como hijo del StaticBody/RigidBody:

```
Floor (StaticBody)
├── MeshInstance
├── CollisionShape
└── FootstepSurface  ← Agregar este nodo
    footstep_profile = footstep_profile_wood.tres
```

### 3. Usar detección por material
1. Crea una `FootstepMaterialLibrary`:
   - Click derecho en FileSystem → New Resource → FootstepMaterialLibrary
   - Agrega elementos FootstepMaterialProfile
   - Asigna cada material y su perfil de sonido

2. Asigna la librería al `FootstepDetector`:
   ```
   FootstepDetector
   └── footstep_material_library = tu_libreria.tres
   ```

## Prioridad de detección

1. **FootstepSurface** - Si el collider tiene un nodo FootstepSurface hijo
2. **Material Library** - Si el material del mesh está en la librería
3. **Fallback** - Usa el perfil genérico asignado

## Crear nuevos perfiles de sonido

1. Click derecho en FileSystem → New Resource → FootstepProfile
2. Arrastra archivos de audio a la propiedad `streams`
3. Ajusta `random_pitch_min/max` y `random_volume_db_min/max`
4. Guarda como `.tres`

## Archivos de audio

Los sonidos están en `res://core_v2/audio/footsteps/`:
- `metal/` - Step_Tile (default)
- `dirt/` - Tierra
- `stone/` - Piedra
- `wood/` - Madera
- `grass/` - Pasto

## Escena de prueba

Ver `core_v2/tests/TestScene_Footsteps.tscn` para ejemplo completo con diferentes superficies.
