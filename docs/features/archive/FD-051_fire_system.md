# FD-051: FireSystem — Amenaza Ascendente del Domo

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-02
**Depends on:** FD-045 (GasParticleManager), FD-036 (GravityManager), FD-042 (over-the-shoulder camera)

**Contexto de diseño:** Vertical Slice del domo único (R~30m, ~6 pisos). El fuego es la
amenaza ambiental que reemplaza al combate. Sube desde abajo; el jugador escapa hacia
arriba. La urgencia es temporal, no de habilidad. Ver sesión de rediseño del bucle.

## Problem

El bucle del Vertical Slice necesita una amenaza que suba por el domo, mate al jugador
por contacto, y presione la escalada vertical. Los dos sistemas existentes no sirven
tal cual para esto:

- `FireEmitter` (FD-045) es un foco de fuego **puntual** (radio 0.5m, altura fija). Sirve
  para braseros y piezas en llamas, no para una pared que asciende.
- `GasArea3D` (FD-045) simula gas con una grilla de densidad **horizontal** (plano X/−Z) y
  un autómata celular que propaga la combustión en el suelo. Su modelo es *gas
  esparciéndose en un piso*, no *fuego subiendo por una torre*. Correrlo a lo alto de seis
  pisos es el eje equivocado y un costo de CPU inviable para HTML5/WebGL (loop por
  partícula + raycast por partícula por frame).

Necesitamos un sistema donde **la amenaza sea lógica y barata**, **el look reutilice la
tecnología de partículas existente**, y **la muerte no sea instantánea** sino mediada por
la resistencia térmica del traje de Elías, para dar una ventana de reacción justa.

## Principio arquitectónico (no negociable)

Separación estricta entre capa lógica y capa visual, consistente con el core determinista:

1. **La amenaza es un solo `float`:** `fire_height`. Sube monótonamente. La muerte se decide
   por comparación de Y contra ese float. Cero partículas involucradas en la lógica.
2. **El visual cabalga sobre `fire_height`** y nunca lo alimenta de vuelta. Las partículas
   son decoración. Si se apagara todo el render, la amenaza seguiría siendo idéntica.
3. **El daño pasa por la resistencia del traje**, no directo a "muerte". El traje absorbe,
   se degrada, y solo cuando su integridad térmica se agota, Elías muere.
4. **Todo lo lógico es determinista y snapshot-able** (`replay_sync`). El visual y la viñeta
   quedan fuera del snapshot (son downstream, reconstruibles desde el estado lógico).

Esto respeta la regla del proyecto: *la simulación nunca lee de la capa visual/HUD; los
triggers disparan por proximidad lógica, nunca por contacto visual.*

## Solution

### Arquitectura

```
FireSystem (Spatial, autoload-por-domo)         [LÓGICA — determinista, snapshot]
├── fire_height : float          ← el único estado que importa
├── fire_speed  : float          ← puede acelerar en el tiempo (la amenaza "aumenta")
├── DebugPlane (MeshInstance)     ← plano rojo semitransparente, dibuja fire_height
└── emite señales: heat_contact(body, dps), fire_height_changed(y)

SuitThermalResistance (Node, componente del Player)  [LÓGICA — determinista, snapshot]
├── integrity : float [0..max]   ← "vida" térmica del traje
├── recibe heat_contact → drena integrity
├── integrity>0: absorbe (no muere)   integrity==0: dispara muerte
└── emite: thermal_state_changed(ratio), suit_breached()

FireVisualBand (Spatial)                        [VISUAL — no determinista, one-way]
└── GasParticleManager (FD-045, reusado)
    └── MultiMeshInstance + gas_flipbook.shader (atlas fireball 8×8)
        ← emite partículas en una banda anular a la altura de fire_height,
          solo en el sector cercano al jugador (LOD). combustion=true siempre.

HeatVignette (Control en OverlayUIManager/CanvasLayer)  [VISUAL — one-way]
└── ColorRect fullscreen con shader de viñeta roja
    ← alpha proporcional a (1 - integrity_ratio) y a heat_contact activo
```

### 1. FireSystem — la pared ascendente (lógica)

Nodo `Spatial`, uno por domo. Posee el estado de la amenaza. En `_physics_process`:

```
fire_height += fire_speed * delta
fire_speed  = base_speed + accel * elapsed        # opcional: la amenaza acelera
emit_signal("fire_height_changed", fire_height)
```

La detección de contacto **no usa un Area física** para la muerte del jugador (evita
depender de solapamiento de colisión y mantiene el determinismo trivial). En su lugar,
compara Y directamente contra los cuerpos registrados en el grupo `fire_vulnerable`:

```
for body in get_tree().get_nodes_in_group("fire_vulnerable"):
    var margin = fire_contact_margin              # zona de "calor" antes del núcleo
    if body.global_transform.origin.y <= fire_height + margin:
        emit_signal("heat_contact", body, damage_per_second)
```

Dos umbrales, no uno, para que el traje tenga sentido:

- **Zona de calor** (`fire_height` .. `fire_height + heat_band`): contacto de calor, drena
  el traje. Es donde Elías "se está quemando" pero aún sobrevive.
- **Núcleo del fuego** (`< fire_height`): si el jugador cae por debajo de la línea real del
  fuego, el drenaje es masivo (multiplicador `core_damage_multiplier`), muerte casi segura.
  Esto castiga caerse al pozo central sin ser un one-shot arbitrario.

**Piezas destructibles (rampas que se derriten):** cualquier prop en el grupo
`fire_destructible` compara su propia Y contra `fire_height`. No necesita simular nada:

```
# En el prop destructible:
if not _melting and FireSystem.fire_height >= global_transform.origin.y - melt_offset:
    _melting = true
    _melt_timer = melt_delay        # 1-2s de gracia visible (se dobla/ennegrece)
# al agotarse: collision_shape.disabled = true; caída o desaparición
```

Un `if` por pieza contra un float compartido. Determinista, barato, y produce el
"el camino se desmorona detrás de ti" que valida el bucle.

### 2. Debug: dibujar el Area3D / la línea del fuego

Requisito explícito. El `FireSystem` incluye un `DebugPlane` (un `MeshInstance` con un
`PlaneMesh` del ancho del domo, material rojo semitransparente sin sombras) posicionado
en `y = fire_height` cada frame. Toggle por export `debug_draw`.

- **`debug_draw = true`:** el plano se ve, más dos líneas de gizmo opcionales para
  `heat_band` (naranja) y núcleo (rojo intenso), dibujadas con `ImmediateGeometry` o
  `DebugDraw`. Permite ver exactamente dónde mata sin depender del render de partículas.
- **`debug_draw = false`:** `DebugPlane.visible = false`. En release el plano nunca se dibuja.
- **`debug_readout`:** opcional, imprime/actualiza `fire_height`, `fire_speed`, integridad
  del traje y ratio en una etiqueta de esquina (reutiliza el patrón de overlay de debug del
  proyecto). Útil para calibrar la velocidad de subida contra los ~30s de escalada limpia.

El plano de debug es intencionalmente el **mismo objeto conceptual** que la amenaza: su Y
*es* `fire_height`. No hay dos verdades. Lo que ves en debug es lo que mata.

### 3. SuitThermalResistance — muerte mediada por el traje

Componente `Node` hijo del Player (o del propio `PlayerControllerV2` vía composición).
Convierte el contacto de calor en degradación gradual antes de matar.

Estado:

```
integrity : float            # 0..max_integrity, empieza en max
is_breached : bool           # true cuando integrity llega a 0
```

En respuesta a `heat_contact(body, dps)` (solo si `body` es este player):

```
integrity -= dps * delta * (core_damage_multiplier if en_nucleo else 1.0)
integrity  = max(integrity, 0.0)
emit_signal("thermal_state_changed", integrity / max_integrity)
if integrity <= 0.0 and not is_breached:
    is_breached = true
    emit_signal("suit_breached")     # ESTO dispara la muerte/respawn de Elías
```

Fuera del contacto de calor, el traje **regenera lentamente** (`regen_per_second`), con un
retardo (`regen_delay`) tras el último contacto. Esto hace que "rozar" el fuego brevemente
sea recuperable, pero quedarse dentro sea fatal — exactamente la tensión de decisión que
busca el diseño, no un castigo binario.

**Coherencia narrativa:** la integridad térmica es del **traje de mantenimiento**, no de
la carne de Elías. Encaja con el canon (el traje es lastre y músculo; también es su
protección para faenar en zonas hostiles). El hook "perder el traje" se refuerza: sin
traje, `max_integrity` sería ~0 y el fuego mata al instante.

La muerte real (respawn, reinicio del loop) la maneja quien escuche `suit_breached` — el
`PlayerControllerV2` o un `RespawnManager`. El `FireSystem` y el componente del traje no
saben de respawn; solo reportan estado. Separación de responsabilidades.

### 4. Visual del fuego con GasParticleManager + flipbooks

Reutilizamos `GasParticleManager` (FD-045) **sin reescribirlo**, configurándolo como banda
de fuego. No usamos `GasArea3D` (su grilla horizontal y su autómata no aportan aquí).

**Assets:** los atlas ya existentes en `assets/flipbook_particles/assets/fireballs/`
(`fireball_01..04.png`), que son **8×8 = 64 frames**. El `gas_flipbook.shader` ya soporta
esto (`atlas_columns=8`, `atlas_rows=8`, `frames_per_second`, y `fire_emission_strength`
cuando `custom_data.y == 1.0` marca combustión). Para el humo de coronación, los atlas de
`smokes/`; para chispazos al derretirse props, `explosions/`.

**Configuración del manager para fuego (FireVisualBand):**

| Parámetro del manager | Valor fuego | Razón |
|---|---|---|
| `default_atlas_path` | `.../fireballs/fireball_01.png` | textura de llama |
| atlas 8×8 (shader) | `atlas_columns=8, atlas_rows=8` | 64 frames del flipbook |
| `flipbook_frames_per_second` | 24–48 | llama viva, no lenta como gas |
| `buoyancy` | negativo fuerte (sube) | flotabilidad térmica hacia arriba |
| `viscosity` | media | que las lenguas no se dispersen de más |
| `ignition_color` | naranja cálido | color de combustión |
| combustión | forzada `true` en cada emit | el shader usa la vía de fuego siempre |
| `collide_with_world` | **false** | crítico: sin raycast por partícula = barato |
| `pool_size` | acotado por LOD (ver abajo) | techo de coste |

**Emisión en banda anular, LOD por cercanía al jugador (clave de rendimiento):**

El fuego llena visualmente todo el anillo del domo, pero **solo emitimos partículas en el
sector cercano a la cámara/jugador**. El resto del anillo, fuera de vista, no gasta
partículas. Cada frame, el `FireVisualBand`:

1. Toma `fire_height` (± una banda vertical de ruido para que la línea no sea plana).
2. Calcula el arco del anillo visible desde la cámara (frustum aproximado / ángulo).
3. Emite partículas solo en ese arco, a esa altura, hasta `pool_size`.
4. Reutiliza el pool circular del manager (ya lo hace por diseño).

Esto acota el costo a "lo que se ve", no "seis pisos de anillo". Es la misma disciplina de
LOD que el resto del exterior (FD-041). Con `collide_with_world=false` y pool acotado, el
fuego es visualmente denso y barato.

**Coronación de humo (opcional v1.1):** un segundo manager con atlas `smokes/`, buoyancy
suave, emitiendo por encima de la línea de fuego, para tapar el borde superior y dar
volumen. Diferible.

**El visual jamás decide muerte.** Las partículas se ven, nada más. Si por LOD no hay
partículas en un sector, el `fire_height` lógico sigue matando ahí igual. Nunca se lee el
estado de partículas para daño.

### 5. Viñeta roja de calor (HUD)

Feedback de pantalla cuando el jugador recibe daño térmico. Vive en el `OverlayUIManager`
(`CanvasLayer`, con `ensure_overlay` + slots), **no** en el `HelmetHUDV2` (que es un
holograma 3D, inservible para fullscreen).

**Implementación:** un `Control`/`ColorRect` a pantalla completa en el slot pasivo, con un
shader de viñeta (radial: transparente al centro, rojo hacia los bordes). Se suscribe a
`thermal_state_changed(ratio)` y a `heat_contact`:

```
alpha_objetivo = base_pulse * heat_activo + (1.0 - ratio) * damage_weight
# heat_activo: pulso mientras hay contacto (respiración de la viñeta)
# (1 - ratio): intensidad crece conforme el traje se degrada
alpha_actual = lerp(alpha_actual, alpha_objetivo, delta * responsiveness)
```

Comportamiento:

- **Sin contacto, traje sano:** viñeta invisible.
- **Contacto de calor:** viñeta roja pulsa suave; se intensifica cuanto más baja la
  integridad. Comunica "te estás quemando" y "cuánto te queda" en un solo canal.
- **Traje casi breached:** viñeta intensa, quizá pulso más rápido / tinte hacia los bordes,
  señal de peligro inminente sin un número de UI.
- **`suit_breached`:** flash pleno antes del respawn (lo dispara la lógica de muerte).

La viñeta es puramente cosmética y **no entra al snapshot**: se reconstruye desde el ratio
de integridad, que sí es determinista. En un replay se recomputa idéntica.

## Determinismo y snapshots

- `FireSystem.get_snapshot()` → `{ fire_height, fire_speed, elapsed }`. Restore fija los
  tres. La pared es reproducible exactamente.
- `SuitThermalResistance.get_snapshot()` → `{ integrity, is_breached, _regen_delay_timer }`.
- Props destructibles: `{ _melting, _melt_timer }` por pieza (ya en `replay_sync` si heredan
  del prop base con snapshot).
- **Fuera de snapshot:** `FireVisualBand` (partículas — el `GasParticleManager` ya tiene su
  propio snapshot para gas, pero para el fuego LOD-emitido lo marcamos como visual puro y
  no lo restauramos; se regenera). `HeatVignette` (deriva del ratio).
- Regla: nada visual escribe en nada lógico. El único acoplamiento es lógica → señal →
  visual, unidireccional.

## Exports

### FireSystem

| Export | Tipo | Default | Descripción |
|---|---|---|---|
| `base_speed` | float | 0.15 | m/s de subida inicial (calibrar vs ~30s de escalada) |
| `accel` | float | 0.0 | m/s² de aceleración (0 = velocidad constante) |
| `start_height` | float | 0.0 | Y inicial de la línea de fuego |
| `heat_band` | float | 2.0 | m sobre la línea donde ya hay daño de calor |
| `fire_contact_margin` | float | 0.5 | holgura de la zona de calor |
| `damage_per_second` | float | 25.0 | drenaje de integridad en zona de calor |
| `core_damage_multiplier` | float | 4.0 | multiplicador bajo la línea real |
| `debug_draw` | bool | true | dibuja el plano rojo + gizmos de banda |
| `debug_readout` | bool | false | overlay de texto con height/speed/integridad |

### SuitThermalResistance

| Export | Tipo | Default | Descripción |
|---|---|---|---|
| `max_integrity` | float | 100.0 | integridad térmica total del traje |
| `regen_per_second` | float | 8.0 | recuperación fuera del calor |
| `regen_delay` | float | 2.0 | s sin contacto antes de regenerar |
| `core_damage_multiplier` | float | 4.0 | espejo del de FireSystem para núcleo |

### FireVisualBand

| Export | Tipo | Default | Descripción |
|---|---|---|---|
| `atlas_path` | String(FILE) | fireball_01.png | atlas 8×8 de llama |
| `frames_per_second` | float | 32.0 | velocidad del flipbook |
| `pool_size` | int | 96 | techo de partículas (coste LOD) |
| `visible_arc_deg` | float | 140.0 | arco del anillo emitido cerca de cámara |
| `line_noise` | float | 0.6 | ruido vertical de la línea de fuego |
| `follow_lerp` | float | 12.0 | suavizado del seguimiento a fire_height |

## Files to Create

- `core_v2/systems/fire/FireSystem.gd`
- `core_v2/systems/fire/FireSystem.tscn` (incluye `DebugPlane`)
- `core_v2/systems/fire/FireVisualBand.gd`
- `core_v2/systems/fire/FireVisualBand.tscn` (contiene un `GasParticleManager` configurado)
- `core_v2/player/components/SuitThermalResistance.gd`
- `core_v2/ui/overlay/HeatVignette.gd`
- `core_v2/ui/overlay/HeatVignette.tscn`
- `core_v2/ui/overlay/shaders/heat_vignette.shader`

## Files to Modify

- `PlayerControllerV2.gd`: añadir al grupo `fire_vulnerable`; alojar
  `SuitThermalResistance`; conectar `suit_breached` → muerte/respawn; exponer un
  `take_damage(amount)` mínimo (compat con la vía `has_method` que ya usa `GasArea3D`).
- Props de rampa/plataforma del domo: añadir al grupo `fire_destructible` y la lógica de
  melt por comparación de Y.
- `OverlayUIManager`: registrar `HeatVignette` en el slot pasivo al entrar al domo.

## Verification

1. **Subida determinista:** dos corridas de `runtest.sh` con la misma semilla → `fire_height`
   idéntico frame a frame (drift = 0.0). El float es la prueba más limpia de determinismo
   del proyecto.
2. **Ventana del traje:** el jugador entra a la zona de calor; `integrity` drena a
   `damage_per_second`; verificar que NO muere hasta `integrity == 0`, y que
   `suit_breached` se emite exactamente una vez en ese instante.
3. **Regeneración:** salir del calor antes de breach; tras `regen_delay`, `integrity` sube;
   confirmar que rozar el fuego es recuperable.
4. **Núcleo letal:** caer bajo `fire_height` aplica `core_damage_multiplier`; muerte rápida
   pero no one-shot arbitrario (drena, no setea a 0 directo).
5. **Debug fiel:** con `debug_draw=true`, el plano rojo coincide con la Y donde empieza el
   daño (probar tocando justo en el borde del plano).
6. **Melt de props:** una rampa marcada `fire_destructible` se derrite `melt_delay` s
   después de que `fire_height` cruza su Y; su colisión se desactiva; determinista en replay.
7. **Coste:** perfilar con el `pool_size` y `visible_arc_deg` por default en el domo de 6
   pisos; objetivo 60 FPS en el target de rendimiento del proyecto. `collide_with_world`
   debe estar en `false` para el manager de fuego.
8. **Viñeta desde estado:** forzar `thermal_state_changed` con ratios fijos y verificar que
   el alpha de la viñeta es función solo del ratio (reproducible, no depende de timing).

## Open [DECIDIR]

- **Velocidad base vs ~30s de escalada:** calibrar `base_speed` para que el jugador limpio
  llegue arriba con margen y el lento se queme. Empezar en ~40–50s de subida del fuego para
  30s de escalada. Ajustar jugando.
- **¿`accel > 0`?** ¿La amenaza acelera (clímax creciente) o es constante (predecible)?
  Probar constante primero; la aceleración es una capa de tensión opcional.
- **Regeneración del traje: ¿sí o no?** La regen hace el sistema más indulgente/casual (lo
  que se pidió), pero podría diluir la urgencia. `[DECIDIR]` tras playtest.
- **Coronación de humo v1 o v1.1:** ¿el segundo manager de humo entra ya o se difiere?
- **Gas inflamable como acelerante:** ¿un `GasArea3D` (en su eje horizontal correcto) en
  algún piso que, al ser alcanzado por `fire_height`, pegue un salto a `fire_speed`?
  Conecta ambos sistemas sin forzar ninguno. Diferible a v1.1.
- **¿Muerte = respawn del loop, o = "archivado" por la IA a la cápsula?** El `suit_breached`
  puede enganchar la narrativa de la IA reinsertándote en criogenia en vez de un game-over
  seco. `[DECIDIR]` con el diseño narrativo.
