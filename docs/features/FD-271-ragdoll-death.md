# FD-271: Muertes con Ragdoll (Desplome de Elías)

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-08-20
**Completed:** -

## Problem

Cuando Elías muere — hoy por congelación: el hielo agota el traje hasta `suit_breached`
(`SuitThermalResistance`) — el flujo pasa directo a la cobertura de muerte
(`death_cover` de `ScreenEffectsManager`) y al respawn. El cuerpo no reacciona
físicamente: queda en su pose/idle mientras la pantalla se funde a negro. Falta el
"desplome": que Elías se desplome con física de ragdoll al morir, para vender el
momento.

## Solution

Añadir un ragdoll basado en `PhysicalBone` (sistema nativo de Godot 3) al personaje
del Pilot (Elías) y activarlo en el instante de la muerte, **antes** de que suba el
`death_cover` y **antes** del respawn. El ragdoll es presentación pura: no toca el
estado determinista de core_v2 ni el replay.

### Flujo de integración

```
hielo agota traje
  -> SuitThermalResistance.suit_breached
  -> PlayerControllerV2._on_suit_breached()
  -> [NUEVO] activar ragdoll del Pilot (desplome)
  -> TeleportSystem._on_player_killed()
  -> begin_death_cover() + wait_for_death_confirm()
  -> respawn (reinstancia Pilot; el ragdoll se limpia)
```

### Punto de inserción

Método `begin_ragdoll()` en el Pilot (`PlayerControllerV2`), invocado desde
`_on_suit_breached()` **antes** de delegar al `TeleportSystem`, para que el desplome
arranque lo antes posible y sea visible antes de que la cobertura tape la cámara.
`TeleportSystem._on_player_killed()` no necesita cambios salvo garantizar que el
respawn limpia cualquier PhysicalBone residual.

### Considered Options

- **A: PhysicalBone nativo** — "Create physical skeleton" sobre el Skeleton del Pilot
  + `physical_bones_start_simulation()`. Pros: nativo, sin dependencias, activa/para
  en un frame, estándar Godot 3. Cons: ajustar joints/collision shapes. **Seleccionada.**
- **B: Simple Ragdoll Wizard (addon)** — genera el ragdoll automáticamente. Pros: menos
  trabajo manual. Cons: dependencia en `addons/`, menos control. (Descartada por ahora.)
- **C: Active Ragdolls (RigidBody + Generic6DOFJoint)** — más control y "músculos".
  Pros: mejor comportamiento activo. Cons: overkill para muerte simple, más
  configuración, requiere Bullet. Va al backlog.

## Notas técnicas (Godot 3, GDScript 1.x)

- `PhysicalBone` son hijos del `Skeleton`. Activar: `skeleton.physical_bones_start_simulation()`;
  parar: `skeleton.physical_bones_stop_simulation()`. Puede limitarse a huesos concretos
  pasando nombres de hueso.
- Los `PhysicalBone` por defecto traen `PinJoint` sin restricciones → "crumpling".
  Ajustar a `ConeJoint` (hombros, cuello, caderas; swing 20–90°, twist 20–45°) y
  `HingeJoint` (codos, rodillas; con angular limit) para un desplome natural.
- Quitar huesos inútiles (MASTER, dedos, utility bones) por rendimiento.
- **Colisiones**: desactivar el `CollisionShape` (cápsula) del `KinematicBody` raíz
  durante el ragdoll para que no interfiera; los PhysicalBone llevan su propia colisión.
  Cuidar collision_layer/mask.
- **AnimationTree**: detener/pausar el `AnimationTree` durante el ragdoll para que la
  animación no pelee contra la física (el skeleton pasa a ser controlado por física).
- **Determinismo/replay**: el ragdoll es visual-only. No debe afectar `HotzoneRecorder`,
  snapshots ni el estado térmico. La muerte sigue determinista vía `suit_breached`.
- **Respawn**: al reinstanciar el Pilot, el ragdoll se limpia con la nueva instancia.
  Asegurar que no queden PhysicalBones huérfanos congelando la física.

## Files to Modify

- `core_v2/actors/Pilot_v2.tscn` (modify) — physical skeleton (PhysicalBone + CollisionShape + joints) bajo `Visual/Pivot/Skeleton`.
- `core_v2/player/PlayerControllerV2.gd` (modify) — `begin_ragdoll()` / `end_ragdoll()`; invocar al morir.
- `core_v2/systems/TeleportSystem.gd` (modify, solo si hace falta) — garantizar limpieza del ragdoll en respawn.
- `core_v2/actors/PilotAnimatorV2.gd` (posible) — pausar AnimationTree durante el ragdoll.

## Verification

1. Morir por congelación (dejar que el hielo agote el traje): Elías se desploma con
   ragdoll en el instante del `suit_breached`, visible antes de que suba el `death_cover`.
2. Respawn correcto: tras confirmar la muerte, el Pilot reaparece en el checkpoint, sin
   ragdoll residual ni física colgada.
3. Determinismo: con replay/hotzone activo, la muerte sigue determinista (el ragdoll no
   introduce deriva en snapshots).
4. Rendimiento: sin ragdoll activo no hay coste (PhysicalBones dormidos).
