# FD-321: SpinFrame — espirales de domos con física rotante real

**Status:** Aprobado para prototipo SpinLab (v1). Parte A implementada; Parte B pendiente.
**Priority:** Alta (habilita el prototipo de física rotante real)
**Effort:** Medio (clase pura + geometría + controlador + cámara + escena de validación)
**Created:** 2026-11-21
**Revised:** 2026-11-21

> **Nota de numeración.** `FD-321` ya está asignado a
> `FD-321_camaras_cinematicas_momentos_clave.md`. Este spec conserva el
> identificador pedido por la tarea; si se publica en el índice de features debe
> renumerarse para no colisionar.

## 1. Problema

Los domos y terrazas actuales usan `WorldRotator`: el mundo y la cámara giran
para que una terraza se vea "parada", pero el jugador sigue en física estándar
de Godot (`Vector3.UP`, gravedad hacia `-Y`). Eso alcanza para caminar, pero no
permite:

- Física rotante real: caída radial, Coriolis y conservación de energía en el
  marco que gira.
- Vuelo libre dentro del cilindro (saltar y quedar en órbita de caída).
- Cerca del eje, donde la gravedad centrífuga tiende a cero.
- Una lectura 2.5D estable de una espiral que gira a ~1.9 rpm.

`WorldRotator` es un truco de presentación y frame-management; no es un motor de
física rotante. Introducir Coriolis o caída radial dentro de los modos 0..3
rompería sus contratos y los replays.

## 2. Objetivo

`SpinFrame` es el marco canónico de un cilindro que gira alrededor del eje Z de
la nave. Sobre ese marco se construye un prototipo aislado (`SpinLab`) con:

1. Una clase pura y determinista que define la matemática del marco rotante.
2. Geometría de domo (`DomeSpiralField`) con un recorrido de tres capas.
3. Un modo `SPIN_REAL` opt-in en `GravityModes`, sin tocar los modos 0..3.
4. Una cámara 2.5D co-rotante con cortes e histéresis.
5. Tests analíticos y de conservación que actúen como compuerta de diseño.

## 3. Alcance

### Dentro de alcance (v1)

- Pilot (controlador del jugador) en el prototipo SpinLab.
- Geometría del cilindro y del domo (`DomeSpiralField`).
- Recorrido completo del cilindro: espiral, cuerda, spokes y columna axial.
- Validación en `SpinLab.tscn` y compuerta de diseño.

### Fuera de alcance (v1)

- ANNA / telemetría nueva específica del prototipo.
- Migración de `OdiseaExterior`, `ScaffoldOrbit` o niveles existentes.
- Conversión axial ↔ centrífuga (cambiar de eje o de marco en runtime).
- Daño estructural, combate, narrativa o scripting de Odisea.
- Reemplazar `WorldRotator` o los modos 0..3.

### Archivos prohibidos en la Parte A

`DomeSpiralField`, `DomeRegistry`, `PlayerControllerV2` y cualquier escena
existente. La Parte A solo agrega la clase pura, el modo opt-in y sus tests.

## 4. Marco canónico

| Parámetro | Valor v1 | Notas |
|-----------|----------|-------|
| Eje de rotación | `+Z` | Origen en el centro de la nave. |
| Extensión axial | `|z| <= 4000 m` | La geometría es estática; el cilindro no se traslada. |
| `g_ref` | `9.8 m/s^2` | Gravedad de referencia en el radio de diseño. |
| `r_ref` | `240 m` | Radio del suelo caminable. |
| `omega` | `sqrt(g_ref / r_ref)` | `~0.20207 rad/s`, `~1.93 rpm`. |
| Velocidad de suelo | `omega * r_ref` | `~48.5 m/s`. |
| "Arriba" local | `-normalize(r_perp)` | El suelo es la pared interior del cilindro. |
| Centrífugo | `omega^2 * r_perp` | Hacia afuera (+radial). |
| Coriolis | `-2 * omega_hat_z x v` | Operador exacto, sin aproximación de Euler. |

Los marcos rotante e inercial coinciden en `t = 0`. Las conversiones
`to_inertial_position(p, omega, t)` y `from_inertial_position(p, omega, t)`
rotan alrededor de Z por `+omega*t` y `-omega*t` respectivamente.

### Zona cercana al eje

`r_perp` es indefinido como dirección cuando su norma tiende a cero. `SpinFrame.up`
usa `fallback_up` normalizado si `|r_perp| < r_eps` (`r_eps = 1e-3` por defecto);
si el fallback es cero, usa `Vector3.UP`. Esta es la única discontinuidad
permitida y debe quedar fuera de la ruta principal caminable.

## 5. Contrato `SpinFrame`

Archivo: `core_v2/systems/SpinFrame.gd` (`extends Reference`,
`class_name SpinFrame`). Clase pura: funciones estáticas, sin nodo, sin estado,
sin aleatoriedad. GDScript 1.x con static typing. Menos de 200 líneas.

| Función | Semántica |
|---------|-----------|
| `omega_for(g_ref, r_ref)` | `sqrt(g_ref / r_ref)`; `0.0` si `r_ref <= 0` o `g_ref <= 0`. |
| `r_perp(p)` | `Vector3(p.x, p.y, 0.0)`. |
| `up(p, fallback_up, r_eps)` | `-normalize(r_perp(p))`, o `fallback_up` normalizado cerca del eje. |
| `a_centrif(p, omega)` | `omega^2 * r_perp(p)`. |
| `a_coriolis(v, omega)` | `-2 * Vector3(0, 0, omega).cross(v)`. |
| `rotate_coriolis(v, omega, dt)` | Rotación exacta de `v` alrededor de Z por `-2*omega*dt`; conserva `|v|`. |
| `step_free_flight(p, v, omega, dt, extra_accel)` | Paso fijo determinista; devuelve `{"position": ..., "velocity": ...}`. |
| `jacobi(p, v, omega)` | `0.5|v|^2 - 0.5*omega^2*|r_perp(p)|^2`. |
| `to_inertial_position` / `from_inertial_position` | Conversión pura rotante ↔ inercial para validación y predicción. |

### Integración

`step_free_flight` no es Euler. El flujo homogéneo (centrífugo + Coriolis) se
resuelve en forma cerrada pasando al marco inercial:

```text
V0 = v + omega_hat_z x p
p(t) = R(-omega*t) * (p + V0*t)
v(t) = R(-omega*t) * V0 - omega_hat_z x p(t)
```

`extra_accel` (propulsores, expresado en el marco rotante) entra con medio kick
al inicio y al final (Strang). Con `extra_accel = Vector3.ZERO` el paso conserva
la integral de Jacobi sin inyectar energía. Criterio de aceptación: error
relativo de Jacobi `< 1e-3` en 30 s a `dt = 1/60` para varias condiciones
iniciales.

## 6. Geometría `DomeSpiralField`

`DomeSpiralField` reemplaza a `TerraceSpiral` en escenas nuevas. `TerraceSpiral`
se conserva tal cual para escenas viejas y no se reserializa.

### Pilot y modo

`Pilot` incorpora `SPIN_REAL = 4`, alineado con
`GravityModes.Mode.SPIN_REAL == 4`. Es un modo opt-in: no se activa por defecto
ni se deriva de `SPIN_WALKABLE`.

### Recorrido de tres capas

1. **Espiral + cuerda.**
   - Espiral caminable adosada a la pared interior del cilindro.
   - Cuerda tensa como atajo entre vueltas: recorrido alternativo más rápido y
     más expuesto a la caída.
2. **Spokes radiales.**
   - Peldaños/escaleras radiales que conectan el hub central con la espiral.
   - v1 reutiliza `LadderV2`; no se crea un sistema de escalada nuevo.
3. **Columna axial `ZERO_G`.**
   - Columna en el eje Z para transitar entre capas sin gravedad centrífuga.
   - Es el único tramo donde `|r_perp|` puede caer dentro de la zona de fallback.

### Cámara 2.5D

- Co-rotante con el cilindro: el jugador ve la espiral como un plano de
  plataformas, no como un mundo que gira a su alrededor.
- Plano de vuelo 3/4 con componente axial: la cámara no es un side-scroller
  puro; conserva profundidad Z para leer los spokes y la columna.
- Corte 2.5D con histéresis: el cambio de plano se dispara al cruzar umbrales de
  ángulo/altura y solo se revierte tras un margen, para evitar flicker.
- La cámara nunca teletransporta ni rota 180°: el punto de vista del jugador es
  continuo (regla de inmersión de `AGENTS.md`).

### `SpinLab.tscn` y compuerta de diseño

`SpinLab.tscn` es la escena aislada de validación. Debe permitir, en una sola
corrida:

- Caminar la espiral completa y usar la cuerda.
- Subir/bajar por un spoke radial.
- Entrar a la columna axial y experimentar `ZERO_G`.
- Saltar al vuelo libre y volver a anclar al suelo.
- Verificar que la cámara 2.5D no corta en cada frame.

La compuerta de diseño se considera aprobada cuando los tests de §8 pasan, la
escena no presenta glitches visuales y el recorrido se completa sin quedar
atrapado en la zona del eje.

## 7. Decisiones cerradas `[DECIDIR]`

| # | Decisión | Valor v1 |
|---|----------|----------|
| 1 | Factor de Coriolis en suelo | `coriolis_ground_factor = 0.3`, exportable. |
| 2 | Cámara 2.5D | Co-rotante con el cilindro. |
| 3 | Plano de vuelo 2.5D | 3/4 con componente axial. |
| 4 | Selección de anclaje | Asistida por mirada. |
| 5 | `v_safe` / `v_slide` | Valores a afinar en SpinLab. |
| 6 | Spokes | Escalera en v1, reutilizando `LadderV2`. |
| 7 | Conversión axial ↔ centrífuga | Fuera de v1. |
| 8 | Propulsores en vuelo | `Delta-v` limitado. |

## 8. Plan por fases

### Fase 0 — SpinFrame + DomeSpiralField

**Parte A (implementada en este cambio):**

- `core_v2/systems/SpinFrame.gd` con la API de §5.
- `GravityModes.SPIN_REAL == 4` y helpers asociados, sin renumerar 0..3.
- Tests: `test_spin_frame.gd` y actualización de `test_gravity_modes.gd`.
- Registro de `SpinFrame` en `_global_script_classes` de `project.godot`.
- Documentación de `SPIN_REAL` en `Gravity_Physics_Contracts.md`.

**Parte B (pendiente):**

- `DomeSpiralField` como geometría nueva; `TerraceSpiral` intacto.
- Esqueleto de `SpinLab.tscn` con el cilindro, la espiral y la columna.
- Sin `PlayerControllerV2` ni escenas existentes modificadas.

**Aceptación:** tests de §9 verdes; `SPIN_REAL == 4`; modos 0..3 sin cambios.

### Fase 1 — Refactor `_up` en Pilot

- Introducir un `_up` dinámico en el Pilot del prototipo, alimentado por
  `SpinFrame.up`.
- Mantener el `_up` fijo en `PlayerControllerV2` para los modos 0..3.
- Los replays de los modos existentes no deben cambiar.

**Aceptación:** el Pilot camina la espiral; la cámara no salta al cambiar de
capa; `test_determinism_v2` sigue verde para los niveles existentes.

### Fase 2 — Física `SPIN_REAL` + cámara 2.5D

- Integrar `step_free_flight` en el controlador del prototipo para vuelo libre.
- Aplicar `coriolis_ground_factor = 0.3` en suelo.
- Anclaje asistido por mirada y `Delta-v` limitado en propulsores.
- Cámara co-rotante, plano 3/4 con componente axial, corte con histéresis.

**Aceptación:** Jacobi estable, caída radial, Coriolis visible pero controlable,
cámara sin flicker.

### Fase 3 — Cuerda, spokes y hub

- Cuerda tensa transitable.
- Spokes radiales con `LadderV2`.
- Columna axial `ZERO_G` y hub de conexión.
- `SpinLab.tscn` completo + tests de recorrido y compuerta de diseño.

**Aceptación:** recorrido de tres capas completo, sin atascos, con capturas de
validación visual.

## 9. Verificación

```bash
# Tests puntuales de la Parte A
./.venv/bin/pytest tests/test_odisea_runner.py -k "test_gravity_modes or test_spin_frame"

# Alternativa directa
./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd
./runtest.sh -a ./core_v2/tests/test_spin_frame.gd
```

Criterios:

- `SPIN_REAL == 4`; `STANDARD_1G..SPIN_DYNAMIC == 0..3` estables.
- Valores analíticos de `r_perp`, `up`, `a_centrif`, `a_coriolis`,
  `rotate_coriolis` y `jacobi`.
- Jacobi con error relativo `< 1e-3` en 30 s para varias condiciones iniciales.
- Caída libre desde `r0 = 0.5 m` con `v0 = 10 m/s` radial: el punto de impacto
  en el marco inercial coincide con la recta inercial con error `< 0.5 m`.

## 10. Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Malestar por rotación a ~1.93 rpm | Cámara co-rotante; validación visual en SpinLab antes de migrar niveles. |
| Escala y velocidades (~48 m/s en suelo) | `v_safe`/`v_slide` se afinan en SpinLab; sin valores fijos en v1. |
| Singularidad en el eje | `up` con `fallback_up`; la columna axial es la única zona permitida. |
| Doble fuente de verdad (`WorldRotator` vs `SpinFrame`) | `SPIN_REAL` es opt-in y exclusivo de SpinLab; modos 0..3 intactos. |
| Deriva numérica y replays | Integración exacta, sin aleatoriedad, `_physics_process` y snapshot determinista en fases posteriores. |
| Física de Godot 3 vs Box3D | El prototipo usa la física estándar del fork; no se promete migración de cuerpos rígidos en v1. |

## 11. Referencias

- `core_v2/systems/SpinFrame.gd`
- `core_v2/systems/GravityModes.gd`
- `core_v2/tests/test_spin_frame.gd`
- `core_v2/tests/test_gravity_modes.gd`
- `docs/engineering/Gravity_Physics_Contracts.md`
- `core_v2/components/TerraceSpiral.gd` (legacy, sin cambios)
