# WFC Flow Metrics — Contrato de alcance del jugador para niveles generados

> Estado: **contrato de fase 1 (W1)**. Este documento es normativo para el generador de
> niveles (WFC) y para su validador. Describe **contratos e invariantes**, no implementación.
> La fuente única de constantes y funciones es `core_v2/systems/flow/FlowMetrics.gd`; el
> documento y el test derivan de ahí.

## 0. Qué resuelve y por qué

Transit-Run es un plataformero 3D de parkour cinético: el jugador corre por defecto, encadena
saltos y usa el impulso como recurso. Los niveles se generan por WFC, así que el generador no
puede "diseñar a mano" cada hueco: tiene que derivarlos de la **física real del jugador**.

Este documento fija:

1. Las constantes medidas del jugador y las funciones analíticas de alcance como función de
   `g` (gravedad efectiva) y del **tick** de simulación.
2. Los **umbrales de flow**: qué fracción del alcance máximo puede exigir la ruta principal,
   cuál queda para desvíos opcionales y a partir de dónde hace falta una herramienta.
3. Las **etiquetas de chunk** (`SprintGap`, `RhythmSteps`, `GlooClimb`, `MagRail`,
   `CuratedSocket`) con sus restricciones paramétricas y su interfaz de socket.
4. El **criterio de validación automatizada por semilla**.
5. Cómo aplica todo esto en el **anillo centrífugo** (`g_eff = ω²·r`).

### Regla de oro

**La ruta principal NUNCA se bloquea con puzles ni con herramientas.** Toda estación curada es
un *Side Socket* opcional con recompensa cinética. La ruta principal se atraviesa **solo con
saltos** dentro del 80% del alcance máximo. Cualquier tramo por encima del 80% es desvío
opcional (90–100%) o, más allá del 100%, exige herramienta (gloo / catenaria / MagRail).

### Zonas Transit-Run

En las zonas Transit-Run se corre por defecto: la ruta principal se calibra a `v_run` (velocidad
de carrera), no a la de caminata. La caminata se reserva para `RhythmSteps` de precisión.

---

## 1. Constantes medidas del jugador

Leídas en runtime de `core_v2/actors/Pilot_v2.tscn` (nodos `Logic/Jump` y `Logic/Movement` y el
`CollisionShape` del cuerpo). **No se hardcodean.** Valores actuales:

| Constante | Símbolo | Valor | Origen |
|---|---|---|---|
| Gravedad | `g` | 14.0 m/s² | `Jump.gravity = -14` |
| Impulso de salto | `v0` | 10.0 m/s | `Jump.jump_force` |
| Corte de salto variable | `v_cut` | 6.0 m/s | `jump_force · min_jump_intensity (0.6)` |
| Ventana mínima de subida | `τ` | 0.08 s | `Jump.MIN_JUMP_TIME` |
| Corte del salto acrobático | `v_acrob` | 14.0 m/s | `Jump.acrobatic_jump_force` |
| Coyote time | — | 0.15 s | `Jump.COYOTE_TIME` |
| Buffer de salto | — | 0.15 s | `Jump.JUMP_BUFFER_TIME` |
| Velocidad caminar | `v_walk` | 2.0 m/s | `Movement.move_speed` |
| Multiplicador de carrera | — | 3.5× | `Movement.run_speed_multiplier` |
| Velocidad de carrera | `v_run` | **7.0 m/s** | `move_speed · run_speed_multiplier` |
| Aceleración en suelo | `a` | 30.0 m/s² | `Movement.acceleration` |
| Fricción en suelo | `f_g` | 30.0 m/s² | `Movement.ground_friction` |
| Fricción en aire | `f_a` | 5.0 m/s² | `Movement.air_friction` |
| Control en aire | — | 0.70 | `Movement.air_control_multiplier` → `a_air = 21.0` |
| Roll (umbral de caída) | — | `vy ≤ -6.0` | `landing_roll_min_fall_vy` |
| Roll (duración / velocidades) | — | 0.48 s / 8.5–13.5 m/s | `landing_roll_*` |
| Roll (fricción / conversión vertical) | — | 3.5 / 0.45 | `landing_roll_*` |
| Tick por defecto | `f_s` | 60 Hz | proyecto |
| Tick handheld (Anbernic) | `f_s` | 30 Hz | adaptive tick |

---

## 2. Alcance analítico como función de `g` y del tick

`g` entra **siempre** como magnitud positiva. En el anillo centrífugo se usa la gravedad
efectiva local `g_eff = ω²·r` (§6), nunca 14.

### Alturas

- Altura máxima (salto completo, botón sostenido):
  `H_max(g) = v0² / (2g)`
  → a `g = 14`: **3.571 m** analítico; **3.660 m** medido a 60 Hz; **3.755 m** a 30 Hz.
  (El tick más bajo sobre-integra la altura: a menor `f_s`, mayor `H` discreta. Ver §7.)

- Altura de un *tap* (soltar tras `τ`, corte a `v_cut`):
  `H_tap(g) = ½·(v0 + (v0 − g·τ))·τ + v_cut² / (2g)`
  → a `g = 14`: **2.041 m** analítico; **2.133 m** medido a 60 Hz; **2.355 m** a 30 Hz.

### Tiempo en el aire

Salto con velocidad vertical inicial `v0` que aterriza `Δh` arriba (`Δh>0`) o abajo (`Δh<0`):

```
t_air(v0, g, Δh) = ( v0 + sqrt(v0² − 2·g·Δh) ) / g
```

Para `Δh = 0` y `v0 = 10`, `g = 14`: **1.429 s** analítico; **1.433 s** medido (ambos ticks).

### Alcance horizontal

Con velocidad horizontal `v` sostenida durante el vuelo:

```
D(v, g, Δh) = v · ( v0 + sqrt(v0² − 2·g·Δh) ) / g
```

Escrito como se usa en el generador (con `v = v_run`):

```
D(Δh) = v_run · ( v0 + sqrt(v0² − 2·g·Δh) ) / g
```

- Salto corriendo en llano (`Δh = 0`): **10.00 m** analítico; **10.04 m** medido (ambos ticks).
- Salto caminando: `v_walk · t_air` = **2.86 m**; medido 2.855–2.876 m.
- Saltar hacia abajo (`Δh < 0`) **extiende** el alcance; hacia arriba lo acorta.

### Arranque y frenado

- Distancia de arranque (`0 → v_run`): `v_run² / (2a)` = **0.817 m**;
  medido **0.875 m** a 60 Hz, 0.933 m a 30 Hz (la curva de respuesta del input agrega un pelín).
- Distancia de frenado (`v_run → 0`): `v_run² / (2·f_g)` = **0.817 m**;
  medido **0.758 m** a 60 Hz, 0.700 m a 30 Hz.

### Cadena roll-jump

Aterrizar con `vy ≤ -6` manteniendo `crouch` (o dentro de 0.14 s / buffer de 0.22 s) dispara el
roll; durante el roll **el salto no se bloquea**. Velocidad horizontal del roll medida: **9.29
m/s** (a `v_run = 7`). Distancia de un salto lanzado desde el roll: **10.29 m** a 60 Hz (10.41 a
30 Hz) — solo ~2.5% más que el salto corriendo (§7.3).

### Cornisa (auto-hang + mantle)

Banda de agarre: el borde debe estar entre `hang_min_grab` y `hang_max_grab` sobre los pies;
`hang_min_grab = max(0.75, h_total·0.42)`, `hang_max_grab = max(min+0.2, min(1.6, h_total·0.9))`,
con `h_total = altura_cápsula + 2·radio = 2.0 m` → banda **0.84–1.60 m**.
Banda medida (barrido 0.15 m, 60 Hz): **0.75–1.50 m**. Alcance efectivo de cornisa
(`H_max + banda superior`): **5.17 m** analítico, **5.16 m** medido a 60 Hz. Para llegar hay que
saltar: el borde se engancha cuando los pies están en la banda y `vy ≤ 0.05` (cerca del ápice).

---

## 3. Valores canónicos (bloque legible por máquina)

El test `core_v2/tests/test_flow_metrics.gd` exporta `user://flow_metrics.json` y compara estos
valores contra lo medido en el motor con tolerancia (15% relativo o 0.30 absoluto, lo que sea
mayor). Mantener este bloque sincronizado con la medición.

```json
{
  "flow_metrics": {
    "note": "Valores medidos a 60 Hz con Pilot_v2.tscn; el test compara dentro de 15%/0.30 m.",
    "h_max": 3.66,
    "h_tap": 2.13,
    "t_air": 1.43,
    "d_max_run": 10.04,
    "d_max_walk": 2.86,
    "start_distance": 0.88,
    "stop_distance": 0.76,
    "roll_jump_distance": 10.29,
    "ledge_mantle_max_height": 5.16
  }
}
```

---

## 4. Umbrales de flow

Sea `D_max(g) = D(v_run, g, 0)` el alcance máximo corriendo en llano, y `H_max(g)` la altura
máxima. A partir de ahí:

| Banda | Fracción del alcance | Uso | Herramienta |
|---|---|---|---|
| **Ruta principal** | **70–80%** de `D_max` / `H_max` | obligatoria, siempre atravesable a salto limpio | nunca |
| **Desvío opcional** | **90–100%** | recompensa cinética, `CuratedSocket` | no (técnica) |
| **Más allá del 100%** | `> 100%` | atajo / verticalidad / overhang | **sí** (gloo, catenaria, MagRail) |

Estas constantes viven en `FlowMetrics` como `MAIN_MIN_RATIO = 0.70`, `MAIN_MAX_RATIO = 0.80`,
`OPTIONAL_MIN_RATIO = 0.90`, `OPTIONAL_MAX_RATIO = 1.00`.

Invariantes:

- `INV-1`: ninguna arista de la **ruta principal** excede `0.80 · alcance` en su `Δh` local.
- `INV-2`: la cadena `salto → roll → salto` es **técnica de habilidad del tramo 90–100%**;
  jamás requisito de la ruta principal.
- `INV-3`: `GlooClimb`, `MagRail` y `CuratedSocket` nunca son puntos de corte (cut vertices) de
  la ruta principal: se pueden omitir sin bloquear la progresión.
- `INV-4`: todo hueco se evalúa con el `g` **local** (§6) y con el tick **más bajo** soportado
  (peor caso = 30 Hz), no con 60 Hz.

---

## 5. Etiquetas de chunk

Cada chunk expone (a) restricciones paramétricas y (b) una **interfaz de socket** común.

### Interfaz de socket (común a todos)

```
Socket {
  entry: { position: Vector3, normal: Vector3, v_expected: float }
  exit:  { position: Vector3, normal: Vector3, v_expected: float }
  optional: bool          # true => el validador puede omitirlo sin romper la ruta
  payload: Dictionary     # parámetros del chunk (ver cada etiqueta)
}
```

Contrato: `entry`/`exit` son anclas de superficie caminable; `normal` es la dirección "arriba"
local (en el anillo apunta al eje, §6). `v_expected` es la velocidad horizontal con la que el
jugador debe llegar/salir (la ruta principal usa `v_run`).

### `SprintGap`

Hueco horizontal a salto corrido en llano.

- `payload`: `{ gap: float, dh: float }`
- Restricción ruta principal: `gap ≤ 0.80 · D(dh, g)`; `optional = false`.
- Desvío opcional: `0.90 · D ≤ gap ≤ 1.00 · D`; `optional = true`.
- `dh > 0` acorta el alcance; `dh < 0` lo extiende (`D(Δh)` de §2).
- Ritmo: el hueco se coloca a una distancia ≥ `0.5 · start_distance` desde la salida de la
  plataforma anterior para permitir acelerar a `v_run`.

### `RhythmSteps`

Serie de plataformas cortas a saltos de cadencia fija (ritmo), no de alcance máximo.

- `payload`: `{ step_gap: float, rise: float, count: int, period: float }`
- Restricción: `step_gap ≤ 0.55 · D(0, g)` y `rise ≤ 0.80 · H_max(g)` por salto.
- `period` (segundos entre despegues) ≥ `t_air(g, Δh)` del salto correspondiente: el ritmo es
  sostenible sin parar.
- `optional = false` si está en la ruta principal (es ruta, no castigo). No exige puzle.

### `GlooClimb`

Ascenso vertical / overhang que supera el alcance del salto.

- `payload`: `{ climb_height: float, charge_cost: float, latch_points: int }`
- Restricción: `climb_height > H_max(g)` (si no, es un `RhythmSteps`); `optional = true`
  **siempre** salvo que sea la única salida del nivel (prohibido por INV-3 en ruta principal).
- Requiere herramienta (multi-tool / gloo). Nunca aparece como requisito de ruta principal.

### `MagRail`

Tramo de raíl magnético (grind) con impulso cinético.

- `payload`: `{ rail_length: float, entry_speed: float, exit_speed: float, slope: float }`
- `optional = true` en ruta principal. `entry_speed` y `exit_speed` son velocidades
  horizontales sobre el raíl; `exit_speed` alimenta el siguiente `SprintGap`
  (`v_expected` del socket de salida).
- Interfaz: dos anclas (`entry`, `exit`) y el raíl como camino; el jugador no puede "caer" del
  raíl salvo salto explícito.

### `CuratedSocket`

Punto de anclaje **opcional** para una estación curada (recompensa cinética: atajo, vista,
boost), colocado fuera de la ruta principal.

- `payload`: `{ socket_id: string, reward: string, reach_ratio: float }` con
  `reach_ratio ∈ [0.90, 1.00]` (desvío opcional).
- `optional = true` **siempre**. INV-3: quitarlo no cambia la atravesabilidad de la ruta.
- Interfaz: un único ancla `entry` donde se engancha la estación; la estación no puede bloquear
  el paso de la ruta principal.

---

## 6. Anillo centrífugo y `g_eff(r)`

El contrato lo consumen el laberinto de MachineBay (`MachineBayLabyrinthStreamer`) y
`bay_vertical` (anillo centrífugo). Por eso **toda métrica se expresa como función de `g`**.

En el anillo, el "arriba" es hacia el eje y la gravedad efectiva depende del radio:

```
g_eff(r) = ω² · r
```

donde `ω` es la velocidad angular del anillo y `r` el radio del punto. Consecuencias directas:

- `H_max(g_eff)`, `D(Δh, g_eff)` y `t_air(g_eff, Δh)` se evalúan con `g = g_eff(r)` en cada
  radio. La ruta principal se calibra al `g_eff` **más bajo** que atraviesa.
- `Δh` (altura) se mide como desplazamiento **radial** (hacia/desde el eje), con el signo según
  se acerque o aleje del eje.
- A mayor `r`, mayor `g_eff` ⇒ saltos más bajos y cortos. El generador no puede asumir un `g`
  constante a lo largo de la ruta: cada chunk lleva su `g_eff` local.
- En `g_eff` bajo (cerca del eje) el alcance crece: los huecos se recortan o se convierten en
  `RhythmSteps` para no pasarse del 80%.

`FlowMetrics` no fija `g`; expone las funciones parametrizadas y el validador las evalúa por
nodo con el `g_eff` local.

---

## 7. Rarezas físicas (con evidencia medida)

Estas son consecuencias verificadas por el test; el generador debe asumirlas, no "corregirlas".

**7.1 En el aire, sin input, casi no se pierde velocidad.**
`air_friction = 5` es 6× menor que `ground_friction = 30`. Además, **con** input la velocidad no
se pierde: el control en aire solo *redirige* hacia `v_run` (el objetivo sigue siendo `v_run`,
no la velocidad actual). Evidencia: `d_max_run` medido = 10.04 m ≈ `v_run · t_air = 7 · 1.429`.
Si hubiera pérdida de velocidad en vuelo, el alcance medido sería menor. Implicación: un salto
conserva el momentum lateral; el alcance de un `SprintGap` depende de la velocidad **de
despegue**, no de la de aterrizaje.

**7.2 El tick bajo infla la altura.**
A `f_s = 60`: `H_max` medido 3.660 m; a `f_s = 30`: 3.755 m (analítico 3.571). La integración
de Godot 3 sobre-integra a dt grande. Por eso INV-4: calibrar contra el tick más bajo. La
diferencia es ~2.6% en altura y ~7% en arranque/frenado.

**7.3 El roll casi no aumenta el alcance.**
El roll da ~9.29 m/s (vs 7 de carrera), pero al saltar desde el roll el **control en aire**
(`a_air = 21`) vuelve a apuntar a `v_run = 7` y frena el excedente. Medido: roll-jump = 10.29 m
contra 10.04 m del salto corrido: **+2.5%**, no el +33% que sugeriría la velocidad de roll. Por
eso la cadena `salto → roll → salto` es técnica de estilo/estabilidad, no una forma de cruzar
huecos mayores: no la uses para justificar huecos del tramo principal.

**7.4 Banda de agarre de cornisa más generosa que "brazos".**
La banda medida (0.75–1.50 m sobre los pies, `h_total = 2.0`) es relativa al **origen** de la
cápsula (= pies). Un borde bastante por encima de la cabeza del jugador todavía engancha.

**7.5 El arranque medido supera al analítico.**
`start_distance` medido (0.875 m) > analítico (0.817 m): la curva de respuesta del input
introduce una rampa corta antes de la aceleración plena. Para el generador, el margen es
conservador (el jugador acelera un poco más lento de lo ideal).

---

## 8. Validación automatizada por semilla

Dado un grafo generado por WFC a partir de una semilla, el validador
(`core_v2/systems/flow/FlowRouteValidator.gd`, consume el diccionario de `FlowMetrics`) debe
comprobar, por semilla:

1. **Existe una ruta principal** desde `entry` a `exit` que use **solo** chunks no opcionales
   (`SprintGap`, `RhythmSteps`) y cumpla `INV-1` en cada arista, evaluando `g_eff` local.
   Si no existe, la semilla se **rechaza**.
2. Ningún `GlooClimb` / `MagRail` / `CuratedSocket` es punto de corte de la ruta principal
   (`INV-3`): al quitarlos, la ruta principal sigue siendo atravesable.
3. Los desvíos opcionales cumplen `reach_ratio ∈ [0.90, 1.00]`; nada que exija más del 100%
   aparece sin herramienta declarada.
4. La ruta principal se evalúa con el peor caso (tick más bajo, `g_eff` más bajo).

Contrato de entrada del validador (diccionario de `FlowMetrics.metrics()`):

```
{ run_speed, walk_speed, h_max, h_tap, t_air, d_max_run, d_max_walk,
  start_distance, stop_distance, gravity, tick_hz,
  thr_main_min_ratio, thr_main_max_ratio, thr_optional_min_ratio, thr_optional_max_ratio,
  thr_main_gap_limit, thr_optional_gap_limit, hang_min_grab, hang_max_grab,
  ledge_mantle_max_height, measured }
```

---

## 9. Cómo se mide (resumen)

- `core_v2/tests/test_flow_metrics.gd` (GdUnit): instancia `Pilot_v2.tscn`, lee las constantes
  vía `FlowMetrics.from_pilot_node`, y mide cada métrica a **60 Hz y 30 Hz** con input real
  (acciones del `InputMap` que lee `InputProviderV2`), avanzando por frames reales del motor.
  Exporta `user://flow_metrics.json` y verifica este documento dentro de tolerancia.
- `core_v2/tests/test_flow_metrics.oys` (OYS): verificación independiente **en el motor** al
  tick por defecto (60 Hz), leyendo las constantes de la escena en runtime.
- `core_v2/systems/flow/FlowMetrics.gd`: fuente única de constantes y funciones puras de `g` y
  tick.
