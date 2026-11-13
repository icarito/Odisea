# FD-293 — Tank Turn Zone: strafe solo en el borde del stick

- **Estado:** Approved (spec listo para implementar)
- **Fecha:** 2026-09-10
- **Autor:** Odiseo (a pedido de Sebastián)
- **Rama:** `feature/FD-293-tank-turn-zone`
- **Prioridad:** Media — calibración de feel de movimiento (core_v2)

## 1. Problema

En modo tanque (core_v2), el strafe lateral se cuela en TODO el recorrido del
stick X. `PlayerMovementV2.process_movement` (~línea 195–206) aplica:

```
lateral_input = move_vec.x * (1.0 - tank_strafe_blend)
```

Con `tank_strafe_blend = 0.9` (Pilot_v2.tscn) hay un 10% de strafe permanente
aunque el jugador quiera solo girar. El feel antiguo (core_v1) era binario:
stick X = giro puro, 0% lateral. Queremos una **zona de giro pura grande** y
strafe solo en el borde externo del stick (deliberado, no colado).

## 2. Solución: zona de turn

Nueva frontera configurable `tank_turn_zone_end` (fracción del recorrido X):

| \|X\| del stick | Comportamiento |
|---|---|
| 0 … `zone_end` | giro puro, 0% strafe |
| `zone_end` … 1.0 | giro completo + strafe con rampa lineal 0 → (1 − blend) |

### Fórmula exacta (en `process_movement`, cuando `is_tank_turn_mode == true`)

```gdscript
var ax := absf(move_vec.x)
if ax <= tank_turn_zone_end:
    lateral_input = 0.0
else:
    var ramp := clampf(inverse_lerp(tank_turn_zone_end, 1.0, ax), 0.0, 1.0)
    lateral_input = signf(move_vec.x) * ramp * (1.0 - tank_strafe_blend)
```

Cuando `is_tank_turn_mode == false` (modo strafe por mouse), lateral queda
EXACTAMENTE como hoy: `lateral_input = move_vec.x` (sin zona, sin blend).

### Compatibilidad por valor de `tank_turn_zone_end`

- `0.0` → comportamiento actual (blend continuo). **Default del código**, para
  no alterar a Programmer_v2 ni escenas existentes.
- `1.0` → modo binario core_v1 (cero strafe siempre).
- `0.75` → target de Pilot.

## 3. Cambios requeridos

1. **`core_v2/player/PlayerMovementV2.gd`**
   - Nuevo export: `@export var tank_turn_zone_end := 0.0` (rango 0.0–1.0),
     junto a los demás exports de tanque.
   - Aplicar la fórmula de la sección 2 en `process_movement`.
   - `get_tank_yaw_delta()` **NO cambia**: el giro sigue usando el X completo
     en todo el recorrido (precisión fina con el stick a la mitad).
2. **`players/elias/Pilot_v2.tscn`** (nodo Logic/Movement), overrides:
   - `tank_turn_zone_end = 0.75`
   - `tank_strafe_blend = 0.75`
   - `tank_turn_speed = 2.0`
   - `tank_turn_ramp_time = 0.0`
   - `tank_turn_transition_time = 5.0`
3. **Test** (GdUnit3, estilo `core_v2/tests/`): extraer la matemática a una
   función estática/pura (p.ej. `tank_lateral_input(x, zone_end, blend)`) y
   cubrir: x=0 → 0; x=zone_end → 0; x=1, zone=0.75, blend=0.75 → ±0.25;
   zone=0 → x*(1−blend) (compat); zone=1 → 0 siempre; y regresión de modo
   strafe: con `is_tank_turn_mode == false`, lateral == move_vec.x completo.

## 4. NO romper (crítico)

- **Latch de strafe post-traversal** (`PlayerControllerV2._begin_post_traversal_strafe_latch`
  / `_update_post_traversal_strafe_latch`, ~líneas 493–520 y 1231–1241): fuerza
  `movement_logic.is_tank_turn_mode = false` con coyote de release (~0.14s) y
  deadzone. Tras una escalada/traversal el jugador debe conservar strafe
  COMPLETO hasta soltar el stick. La zona SOLO aplica con
  `is_tank_turn_mode == true`. Cualquier path que deje la zona activa durante
  el latch es un bug.
- **Transición mouse→strafe** (`update_tank_mode`, ~líneas 115–135): el mouse
  apaga el modo tanque; al re-entrar en tanque la zona aplica de nuevo. No
  tocar esa lógica.
- **Replay/determinismo**: no agregar estado runtime nuevo ni tocar
  snapshot/restore (la zona es config estática de escena).
- No tocar `Programmer_v2.tscn` ni otras escenas (quedan en default 0.0).
- Los valores de tuning ya fueron decididos arriba; no recalibrar por cuenta
  propia.

## 5. Criterios de aceptación

- [ ] Tests GdUnit3 nuevos pasan en aislamiento (F6).
- [ ] Con Pilot_v2: stick X a mitad de recorrido = giro sin desplazamiento lateral.
- [ ] Stick X al borde = strafe perceptible (rampa), giro intacto.
- [ ] Tras traversal (escalera), strafe completo funciona con el latch activo.
- [ ] Mouse → modo strafe funciona igual que hoy.
- [ ] Sin divergencias de replay (sin estado runtime nuevo).
