# AGENTS.md — Guía breve para agentes (Odisea)

Propósito: fuente de verdad compacta para asistentes IA y desarrolladores sobre reglas críticas del proyecto (Godot 3.6, GLES2).

## Tips rápidos Godot 3.6
- Ternario: `a if cond else b`.
- Declarar variables con `=` y preferir type hints: `var x: int = 0`.
- No editar `.tscn` manualmente; reimportar si hace falta. Colores en .tscn usan RGBA (0–1).
- Nunca pasar `nil` a funciones que esperan bool/Vector2/Vector3; usar valores por defecto seguros.

## Objetivo (MVP Acto I)
- Juego 3D en Godot 3.6 (GLES2): 3ª persona, plataformas móviles/conveyors y narrativa JSON.

## Contratos críticos (resumen)
- `PlayerController.gd` (KinematicBody):
  - Exponer `set_external_velocity(v: Vector3) -> void` (suma con decaimiento por frame).
  - Usar `move_and_slide_with_snap(motion, snap_vec, Vector3.UP, true)`; `snap_vec = -get_floor_normal() * snap_len` cuando esté en suelo.
  - Implementar coyote time (~120–150 ms) e input buffer (~100–120 ms) para saltos.
- `MovingPlatform.gd`:
  - Calcular velocidad instantánea (Δpos / Δt) y comunicarla a cuerpos pasajeros (Area/detección).
  - Mantener lista de pasajeros y llamar `set_external_velocity()` según corresponda.
- `Conveyor.gd` (Area):
  - Aplicar `push_velocity` a KinematicBody/RigidBody; para el jugador usar `set_external_velocity`.
  - Exports: dirección y magnitud; visual coherente (flechas).
- Diálogos:
  - `autoload/DialogueManager.gd`: cargar JSON, exponer `start_dialogue(id)` y señales; reproducir voz con `AudioStreamPlayer3D`.

## Normas de trabajo relevantes
- Cambios pequeños y enfocados por feature; validar movimiento en `src/core_v2/scenes/TestScene_v2.tscn`.
- Documentar exports críticos en el Inspector con valores por defecto razonables.
- Tests: usar GdUnit3 (API fluida).
- CI: separar args de motor vs usuario con `--`.

## Refactor / política de scripts
- Proyecto en proceso de refactor a `src/core_v2`.
- Regla: todos los scripts `.gd` nuevos o refactorizados deben residir en `src/core_v2`.
- No crear archivos `.gd` fuera de `src/core_v2` sin aprobación explícita.