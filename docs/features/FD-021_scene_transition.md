# FD-021: Scene Transition System

**Status:** Design
**Priority:** P0
**Effort:** Medium
**Created:** 2026-03-02

## Problem

Odisea necesita moverse entre interiores, airlocks, terrazas centrifugas y
escenas de nave sin que el jugador perciba cortes duros. La respuesta de
producto para Acto I es usar varias escenas pequenas/terrazas conectadas por
`SceneManager`, no una escena monolitica.

La fantasia principal de transicion debe ser **airlock**. Fade o mascara corta
son aceptables si ayudan a ocultar carga, pero deben sentirse como parte del
airlock/camara, no como una pausa de menu.

## Solution

Implementar un `TransitionPortal` liviano que use el `SceneManager` existente en
vez de crear un sistema paralelo.

### Existing Runtime To Reuse

| File | Role |
|------|------|
| `core_v2/autoloads/SceneManager.gd` | Carga escenas con `ResourceLoader.load_interactive()`, captura snapshot del player, aplica `target_spawn_id` y restaura input. |
| `core_v2/autoloads/TransitionLayer.gd` | Fade/loading fallback. |
| `core_v2/props/AirlockChamber.tscn` | Boceto visual/interactivo de airlock. |
| `core_v2/components/AirlockControllerV2.gd` | Logica deterministica de puertas/presurizacion; base para el ciclo local del airlock. |
| `SpawnPointV2` | `SceneManager` ya lo busca para posicionar el player por `spawn_id`. |

### TransitionPortal Contract

Nuevo componente propuesto:

```gdscript
export(String, FILE, "*.tscn") var target_scene
export(String) var target_spawn_id := ""
export(String, "airlock", "fade", "instant") var transition_style := "airlock"
export(bool) var preserve_player_state := true
export(float, 0.0, 3.0) var fade_out := 0.2
export(float, 0.0, 3.0) var fade_in := 0.2
```

Responsabilidades:

- detectar al player o recibir `interact()`;
- opcionalmente iniciar el ciclo de `AirlockControllerV2`;
- llamar a `/root/SceneManager.goto_scene(target_scene, params)`;
- pasar `target_spawn_id`, `preserve_player_state`, `transition`, `fade_out`,
  `fade_in` y cualquier `state_data` necesario;
- no mover al player directamente si `SceneManager` puede hacerlo via spawn.

### First Vertical Test

Crear una escena minima de prueba:

```text
Interior_A.tscn
+-- Player/Pilot
+-- AirlockChamber
+-- TransitionPortal_ToTerraceA

Terrace_A.tscn
+-- SpawnPointV2(spawn_id="from_interior_a")
+-- WorldRotator
+-- PlateContentRoot
```

La primera meta es ida/vuelta con transform y modo de gravedad preservados. La
segunda meta es que el airlock oculte la carga con una mascara corta si hace
falta.

## Files to Modify

- `core_v2/components/TransitionPortal.gd` (new)
- `core_v2/components/TransitionPortal.tscn` (new, optional)
- `core_v2/props/AirlockChamber.tscn` (modify only if needed)
- `core_v2/components/AirlockControllerV2.gd` (modify only if needed)
- Test/layout scenes for the Acto I slice

## Files Not To Create

- No crear un `SceneTransition.gd` paralelo bajo `core_v2/sim` si
  `SceneManager` ya cubre la carga y restauracion de estado.

## Verification

1. Player entra/interactua con airlock y se dispara la transicion.
2. Nueva escena carga via `SceneManager`.
3. Player aparece en `SpawnPointV2` correcto por `target_spawn_id`.
4. Snapshot del player se preserva salvo override explicito.
5. Input queda desactivado durante la transicion y restaurado al final.
6. Ida/vuelta entre interior y terraza no deja escenas superpuestas ni player
   duplicado.
7. Modo de gravedad/controller se preserva o se reestablece por zona de forma
   deterministica.
