# FD-021: Scene Transition System

**Status:** Implemented
**Priority:** P0
**Effort:** Medium
**Created:** 2026-03-02
**Updated:** 2026-05-29
**Completed:** 2026-05-29

## Problem

Odisea necesita moverse entre interiores, airlocks, terrazas centrifugas y
escenas de nave sin que el jugador perciba cortes duros. La respuesta de
producto para Acto I es usar varias escenas pequenas/terrazas conectadas por
`SceneManager`, no una escena monolitica.

La fantasia principal de transicion debe ser **airlock**. El jugador camina por
un tunel de ~8m mientras la escena de destino carga en background, manteniendo
control total. Al llegar al otro lado, la transicion ocurre y aparece dentro del
airlock correspondiente en la nueva escena.

## Solution

### Arquitectura: AirlockZone (zona, no portal)

En vez de un portal puntual que se activa al entrar, usar **AirlockZoneV2** que
extiende BaseZoneV2 y cubre todo el tunel del airlock:

```
AirlockChamber (Spatial)
├── AirlockControllerV2 (script) — ciclo de puertas
├── CylindricalShell (CSGCombiner) — visual + collision
├── OuterDoor (IrisDoorV2)
├── InnerDoor (IrisDoorV2)
├── ChamberZone (Area) — detecta player dentro
├── AirlockZoneV2 (BaseZoneV2 ext) — Zona larga ~8m
│   ├── export target_scene, target_spawn_id
│   ├── body_entered → empieza a cargar Scene B en background
│   ├── physics_process → trackea progreso (0-100%) del player dentro de la zona
│   └── al ~90% → dispara transicion con fade
└── AirlockLight (luces indicadoras de estado/carga)
```

#### Proceso completo (5 pasos):

1. **Player entra al airlock** (un extremo del tunel)
   - `AirlockZoneV2._on_zone_entered()` se dispara
   - Inicia carga asincrona de Scene B via `ResourceLoader.load_interactive()`
   - Puerta de entrada se cierra detras del player (AirlockControllerV2)
   - Player mantiene control total, puede caminar, mirar, etc.

2. **Player camina por el tunel** (~8m de recorrido)
   - `AirlockZoneV2` trackea `_progress` en `_physics_process`:
     - Calcula fraccion del tunel recorrida (0.0 a 1.0)
     - Almacena `_relative_position` (posicion local del player dentro de la zona)
   - Luces del airlock: parpadean sutilmente mientras carga Scene B

3. **Scene B termina de cargar** (en cualquier momento durante el recorrido)
   - La escena pre-cargada se mantiene en memoria, no se instancia aun
   - Luces del airlock cambian a verde fijo listo

4. **Player alcanza ~90% del tunel** (cerca de la puerta de salida)
   - Si Scene B NO ha cargado: player frena suavemente hasta que complete
   - Si Scene B SI ha cargado:
     - Fade out (0.2s)
     - Captura snapshot del player (posicion, velocidad, camara)
     - SceneManager.goto_scene() con:
       - `target_spawn_id`
       - `state_data.player_snapshot`
       - `state_data.airlock_relative_position` (para preservar posicion relativa)
       - `state_data.airlock_relative_transform` (matriz completa para orientacion)

5. **En Scene B, player aparece dentro del airlock opuesto**
   - La escena B se instancia con el `SpawnPointV2` del airlock de destino
   - El player se re-posiciona a la misma posicion relativa dentro del airlock
   - La puerta de salida (que en Scene A era la puerta lejana) se abre automaticamente
   - Fade in (0.2s)
   - Player sale caminando del airlock hacia la nueva escena

### AirlockZoneV2 — Especificacion

```gdscript
# AirlockZoneV2.gd — extends BaseZoneV2
export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(NodePath) var airlock_controller_path
export(Vector3) var zone_dir := Vector3.FORWARD  # direccion del tunel

var _progress := 0.0           # 0.0 a 1.0
var _relative_position := Vector3.ZERO
var _background_load := null   # ResourceLoader.load_interactive() ref
var _scene_ready := false
var _player_in_zone := false
var _has_triggered := false
var _stalling := false         # true cuando frena por carga incompleta

func _on_zone_entered(body):
    # 1. Iniciar carga background
    _background_load = ResourceLoader.load_interactive(target_scene)
    _player_in_zone = true

func _physics_process(delta):
    if not _player_in_zone: return
    var player = _get_player()
    if not player: return
    
    # 2. Calcular progreso a traves del tunel
    var local_pos = global_transform.affine_inverse().xform(player.global_transform.origin)
    var dir = zone_dir.normalized()
    _progress = clamp(local_pos.dot(dir) / zone_length, 0.0, 1.0)
    _relative_position = local_pos
    
    # 3. Poll background load
    if _background_load != null and not _scene_ready:
        var err = _background_load.poll()
        if err == ERR_FILE_EOF:
            _scene_ready = true
            _background_load = null
    
    # 4. Stalling si no ha cargado aun
    if _progress >= 0.85 and not _scene_ready:
        _stalling = true
        # Reducir velocidad del player suavemente
    
    # 5. Disparar transicion
    if _progress >= 0.9 and _scene_ready and not _has_triggered:
        _trigger_transition(player)
```

### AirlockChamber — Dimensiones

- **Forma**: Cilindrica (CSGCylinder, rotable para cualquier angulo)
- **Radio interior**: 3.5m (camara no roza paredes)
- **Largo**: 8.0m (~3-4 seg caminando)
- **Collision**: incluir capa de camara
- **Puertas**: IrisDoorV2 escalada en cada extremo

### Existing Runtime To Reuse

| File | Role |
|------|------|
| `core_v2/autoloads/SceneManager.gd` | goto_scene + load_interactive |
| `core_v2/components/BaseZoneV2.gd` | Clase base |
| `core_v2/components/AirlockControllerV2.gd` | Ciclo de puertas |
| `core_v2/props/IrisDoorV2.tscn` | Puertas |
| `SpawnPointV2` | Spawn por spawn_id |

### Pairing

- 1:1 por airlock. Convencion: `target_spawn_id = "from_X"`, SpawnPointV2 con `spawn_id = "from_X"`

## Files Created

- `core_v2/components/AirlockZoneV2.gd`

## Files Modified

- `core_v2/autoloads/SceneManager.gd` — camera yaw/pitch preservado en snapshot
- `core_v2/components/AirlockControllerV2.gd` — start_transition_cycle + open_exit_door
- `core_v2/levels/Interior_A.tscn` — airlock integrado
- `core_v2/levels/Terrace_A.tscn` — destino funcional

## Camera Yank Fix

El camera yank al transicionar se resolvió preservando `yaw` y `pitch` en el
snapshot del player. `SceneManager._apply_spawn_and_state()` ahora restaura la
orientación completa de la cámara (yaw + pitch) después del spawn, eliminando
el salto brusco.

## Verification

1. Player entra, camina 3-4s con control total
2. Scene B carga en background (sin pausa)
3. Luces del airlock parpadean mientras carga
4. Aparece DENTRO del airlock en B (misma posicion relativa)
5. Puerta opuesta se abre automaticamente
6. Si carga lenta: player frena suavemente
7. Ida/vuelta funciona
8. Camara no atraviesa paredes ni salta en la transicion
9. `./runtest.sh -a ./core_v2/tests/` pasa completo
