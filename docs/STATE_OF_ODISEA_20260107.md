# Estado Técnico — Odisea (2026-01-07)

Documento actualizado tras limpieza y refactor core. Resume stack, arquitectura actual, sistemas implementados y roadmap MVP.

## Resumen Ejecutivo
- **Motor**: Godot 3.6.2 (GLES2)
- **Render**: GLES2 (compatibilidad máxima)
- **Núcleo Jugable**: Tercera persona determinista con `core` (KinematicBody, AnimationTree, replay)
- **Sistema Pivote**: `MovingPlatform.gd` — plataformas móviles deterministas con snapshots y replay validado
- **Estado**: Proyecto limpio, tests pasando (drift < 0.000009), listo para reimplementar sistemas y features MVP

## Stack y Configuración
- **Godot**: 3.6.2 (GLES2)
- **Renderer**: GLES2 (`quality/driver/driver_name="GLES2"`)
- **Plataformas**: Linux/X11, Android (export presets listos)
- **Display**: Fullscreen, 640x480 base, viewport stretch
- **Input**: Acciones (forward/backward/left/right, jump, sprint, aim, etc.) + soporte joystick virtual

## Arquitectura Cleanslate (Core_V2)
- **Input**: `core/input/InputData.gd` + `InputProvider.gd` — abstracción de input para LIVE/REPLAY
- **Sim**: `core/sim/` — movimiento (PlayerController.gd, PlayerMovement.gd, PlayerJump.gd, Conveyor.gd)
- **Things**: `core/things/MovingPlatform.gd` — plataformas móviles deterministas (✅ Referencia)
- **View**: `core/view/PilotAnimator.gd` — animación
- **Scenes**: `core/levels/TestScene.tscn` — test harness
- **Tests**: `core/tests/test_determinism.gd` — validación de replay (PASS)
- **Autoloads**: `core/autoloads/SessionManager.gd` — session management
- **Data**: `core/replay/` — grabación y reproducción de replays

## Sistemas Integrados
- Menú principal (`scenes/Menu.tscn`)
- UI y efectos visuales básicos

## Sistemas Requieren Reimplementación
- BGM mínimo (Menu + criogenia)
- Kill/Respawn + Checkpoints
- Conveyor y WindZone
- Multiplayer split-screen

### Nuevas Features
1. Plataformas con barandas
2. Tubos conectores
3. Objetivo (beacon)
4. Bloques apilables
5. Spawn cinematográfico
6. Obstáculos (plasma leaks)
7. Drones patrulleros
8. Ventanal final + diálogos
9. Cargol

## Convenciones de Proyecto
- Todos los sistemas sincronizables deben pertenecer a grupo `replay_sync`
- Implementar `get_snapshot()` / `restore_snapshot()`
- Lógica de simulación solo en `_physics_process(delta)`
- Input consumido vía `InputProvider` (LIVE) o desde estado interno (NPCs)
- Tests ejecutados con `./runtest.sh -a ./core/tests/test_determinism.gd`

## Archivos Legacy Archivados
- legacy_archive/ — removed
- tests/ — removed
- scripts/replay, scripts/multiplayer, scripts/utils, scripts/ui, scripts/tools — removed
- Autoloads: AudioSystem, GameGlobals, GameConfig, PlayerManager, InputState, FixedPoint, TouchCounter, UIManager — removed
- Orphans archivados en `archive/orphans_20260107/`

## Referencias Documentación
- [AGENTS.md](AGENTS.md) — contratos y normas de trabajo
- [missing_features_act1.md](missing_features_act1.md) — especificación de features MVP
- [DONE.md](../DONE.md) — tareas completadas
- [TODO.md](../TODO.md) — roadmap accionable
