# AGENTS.md — Guía de Desarrollo (Odisea)

Fuente de verdad sobre reglas y contratos del proyecto (Godot 3.6, GLES2) para IA y desarrolladores.

## Tips rápidos Godot 3.6
- Ternario: `a if cond else b`.
- Declarar con type hints: `var x: int = 0`.
- No usar `nil` donde se esperan tipos concretos (bool, Vector2); usar valores por defecto.
- Usar `_nombre` para miembros de uso interno (no hay private/protected).

## Objetivo (MVP Acto I)
- Juego 3D en Godot 3.6 (GLES2): 3ª persona, plataformas móviles/conveyors

## Contratos Críticos
- **PlayerController**: `set_external_velocity(v: Vector3)` para fuerzas externas (plataformas). Usar `move_and_slide_with_snap()`. Implementar coyote time e input buffer.
- **MovingPlatform**: Calcular y comunicar su velocidad a los pasajeros vía `set_external_velocity()`.
- **Conveyor**: Aplicar velocidad a cuerpos en su área, usando `set_external_velocity()` para el jugador.
- **Signals**: Las señales no deben usarse para lógica que afecte el estado físico (posición, velocidad). Su uso debe limitarse a efectos no deterministas (sonido, animaciones, UI). Por ejemplo, `PilotAnimatorV2` puede escuchar señales para disparar animaciones, pero no debe alterar el `state` del `PlayerController`.

## Normas de Trabajo
- Commits pequeños y enfocados. Validar cambios en `TestScene_v2.tscn`.
- Documentar `export var` en el Inspector.
- Usar GdUnit3 para tests.
- **Todo el código nuevo o refactorizado debe ir en `src/core_v2`**.

## Contrato de Replay Determinístico

Para garantizar replays determinísticos, todo agente sincronizado debe:

1.  Pertenecer al grupo `replay_sync`.
2.  Implementar `restore_snapshot(data: Dictionary)`.
3.  Ejecutar toda la lógica de movimiento/simulación en `_physics_process(delta)`. **Nunca en `_process(delta)`**.
4.  Consumir input a través de `InputProviderV2` (jugador) o basarse solo en estado interno (NPCs).

### Ejecución de Tests de Determinismo

```shell
# Ejecutar el test de determinismo para core_v2
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```

Este comando utiliza el script `runtest.sh` para lanzar Godot en modo headless y ejecutar la suite de tests especificada. Si el `drift` (desviación) entre la posición final del replay y la esperada supera un umbral mínimo, el test fallará, indicando una ruptura en el determinismo.