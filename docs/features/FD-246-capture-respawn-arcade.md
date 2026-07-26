# FD-246: Captura, Respawn y Presión Arcade

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-07-26
**Depends on:** FD-245 (DDC Containment Drone)

## Problem

Con DDC de contacto=contención (FD-245), se necesita un loop de fracaso rápido que mantenga el ritmo arcade. Sin pantalla de game over, sin menú de continuar, sin fricción. El jugador falla y en 2-3 segundos está de vuelta en acción.

Además, necesitamos un sistema de checkpoint que aproveche la narrativa: Odisea no quiere matarte, solo reubicarte. Cada captura es una oportunidad para avanzar la historia o la manipulación psicológica.

## Solution

Sistema de captura→respawn con feedback inmediato y checkpoint transparente. Sin menús, sin loading screen, sin romper el flow.

### Loop de captura (secuencia completa)

1. **DDC hace contacto con Elías** → DDC entra en estado CONTAINING.
2. **0.5s de animación:** campo de stasis alrededor de Elías (efecto visual hexagonal/energía). Elías flota ligeramente, inmovilizado. La pantalla se tiñe levemente de azul.
3. **Voz de Odisea:** una línea de diálogo corta (1-3 segundos). "Te dije que no corrieras, Elías." "La obediencia es más eficiente." Varía según contexto y cuántas capturas lleva el jugador.
4. **Fade a negro (0.3s) + respawn (0.3s fade in)** → Elías reaparece en el último checkpoint.
5. **Total:** ~2-3 segundos desde contacto hasta control recuperado.

### Checkpoints

- **Checkpoint visual:** consolas de pared con luz verde (activo) o ámbar (inactivo). Al tocarlas, emiten sonido de confirmación y luz verde pulsante breve.
- **Auto-checkpoint al entrar a una sala nueva.** Si el jugador muere al primer DDC de una sala, no retrocede dos salas.
- **Sin límite de vidas.** Loop infinito. El castigo es perder progreso de sala y escuchar a Odisea.
- **Estado del nivel:** al respawnear, los DDC ya neutralizados (stun permanente o destruidos por Cargol) NO reaparecen. El progreso de sala se conserva parcialmente. Los DDC activos vuelven a sus posiciones de spawn.

### Contador de capturas

- **Visible en HUD** (opcional, discreto). "Contenciones: 3"
- **Odisea reacciona:** después de N capturas, el diálogo cambia de tono. "Eres persistente. Eso es... admirable. O tal vez estúpido."
- **No es game over nunca.** Es una estadística, no un límite.

### Efectos visuales del campo de stasis

- Malla hexagonal azul/blanca alrededor de Elías.
- Partículas de energía flotando hacia arriba.
- Sonido: zumbido grave + tono agudo decreciente (como un sistema apagándose).
- La cámara se aleja ligeramente (lerp a posición más lejana) durante la contención.

### Arquitectura

```gdscript
# core_v2/systems/CaptureSystem.gd (Autoload o nodo de nivel)
extends Node

signal player_contained(capture_count: int)
signal player_respawned(checkpoint_position: Vector3)

var capture_count: int = 0
var active_checkpoint: Vector3
var is_containing: bool = false

func trigger_capture() -> void:
    # 1. Bloquear input del jugador
    # 2. Reproducir animación campo de stasis
    # 3. Diálogo de Odisea (aleatorio del pool)
    # 4. Fade + teletransporte a checkpoint
    # 5. Restaurar input
    pass
```

### Checkpoint Manager

```gdscript
# core_v2/systems/CheckpointManager.gd
extends Node

var checkpoints: Array = []
var active_checkpoint_index: int = 0

func register_checkpoint(position: Vector3, node: Node) -> void:
    pass

func set_active_checkpoint(position: Vector3) -> void:
    pass

func get_respawn_position() -> Vector3:
    return active_checkpoint
```

### Considered Options

- **Option A**: Captura → respawn instantáneo con diálogo breve — **Selected**. Ritmo arcade, sin fricción, aprovecha la narrativa.
- **Option B**: Captura → pantalla de game over → menú de continuar — descartado, rompe el flow y contradice "Odisea no mata".
- **Option C**: Captura → Elías es "reprogramado" y pierde habilidades — descartado para MVP, interesante para Acto II.

## Files to Modify

- `core_v2/systems/CaptureSystem.gd` (nuevo) — lógica de captura/respawn
- `core_v2/systems/CheckpointManager.gd` (nuevo) — gestión de checkpoints
- `core_v2/props/CheckpointConsole.tscn` (nuevo) — prop visual de checkpoint
- `core_v2/props/CheckpointConsole.gd` (nuevo)
- `core_v2/ui/CaptureOverlay.gd` (nuevo) — UI del campo de stasis + fade
- `core_v2/ui/CaptureOverlay.tscn` (nuevo)
- `core_v2/player/PlayerControllerV2.gd` (modificar) — exponer input lock para captura
- `core_v2/tests/test_capture_respawn.gd` (nuevo)

## Verification

1. DDC toca al jugador → secuencia de contención (animación + diálogo)
2. Total time from contact to playable ≤ 3 segundos
3. Respawn en último checkpoint activo
4. Checkpoint se activa al interactuar con consola
5. Auto-checkpoint al cruzar umbral de sala
6. Contador de capturas se incrementa y persiste en la sesión
7. Input del jugador bloqueado durante contención, restaurado tras respawn
8. Múltiples capturas → diálogos de Odisea varían
9. Deterministic replay compatible (captura/respawn son eventos deterministas)
10. Sin pérdida de frames ni stutter durante la transición
