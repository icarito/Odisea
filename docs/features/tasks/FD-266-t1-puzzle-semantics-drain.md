# FD-266 t1 — Refrigerante: despresurizar para reparar, y drain del tanque

## Objetivo

Hoy, en el sistema de criocoolant, **cerrar una válvula hace desaparecer la fisura del caño**.
`CoolantLeak._on_valve_state_changed()` llama `seal()` al cerrar, el estado cae a `SEALED` y de ahí
a `HEALTHY`, y `_has_been_sealed` impide que vuelva a dispararse. Leído por un jugador, eso dice
"cerrar la llave suelda la grieta", que no tiene sentido.

Hay que cambiar la semántica para que el puzle se entienda:

```
FUGA ACTIVA (presión alta)
   │  el tanque drena mientras el refrigerante escapa con presión
   ▼  cerrar la válvula aguas arriba
TRAMO DESPRESURIZADO (presión ~0)
   │  la fuga deja de escupir — el caño SIGUE roto
   ▼  disparar gloo
PARCHE FIRME (no caduca)
   │
   ▼  reabrir la válvula
FLUJO NORMAL — el tanque deja de drenar
```

La regla central: **el gloo solo agarra firme en un tramo despresurizado.** Parchear con presión
encima da un parche provisorio que salta a los pocos segundos.

Con eso cada pieza gana función: la válvula despresuriza, el manómetro dice si es seguro
disparar, el gloo repara, y el tanque es el reloj.

El diseño completo está en `docs/features/FD-266_coolant_puzzle_semantics.md`. **Léalo antes de
empezar**; este brief es la parte a implementar.

## Contexto del sistema

- El juego es **Godot 3.6, GDScript 1.x**. `yield`, no `await`. Todo el código vive en `core_v2/`.
- El proyecto corre en **GLES2**: el nodo `Particles` no se renderiza, se usa `CPUParticles`.
  (Esta tarea no debería tocar partículas, pero conviene saberlo.)
- **Determinismo de replay — contrato duro, ver `AGENTS.md` §5.3.** Nada de `randf()`,
  `randomize()`, `Engine.get_frames_drawn()` ni nada no reproducible en lógica de estado. La
  lógica va en `_physics_process`. Todo nodo con estado está en el grupo `replay_sync` y expone
  `get_snapshot() -> Dictionary` / `restore_snapshot(data: Dictionary)`. Si agrega estado nuevo,
  **tiene que entrar en el snapshot**.
- Español neutro en comentarios y textos de UI. Sin voseo argentino.
- Los comentarios explican **por qué**, no qué. Mire el estilo de los archivos que va a tocar: son
  párrafos cortos que justifican una decisión, no glosas línea por línea.

### Las piezas que ya existen y cómo se hablan

- `core_v2/systems/cryo/CoolantLeak.gd` — máquina de estados de la fuga
  (`HEALTHY → WARNING → LEAKING → SEALED`), `get_leak_intensity() -> float` de 0 a 1.
  Se conecta a la señal `valve_state_changed(is_open)` de un `PipeValve` vía `valve_path`.
- `core_v2/props/pipe/PipeValve.gd` — `extends InteractableBaseV2`. Tiene `is_active` (abierta) y
  emite `valve_state_changed(is_open)`.
- `core_v2/props/pipe/CoolantTank.gd` — `tank_level` de 0 a 1, `drain_rate` (hoy fijo, default 0),
  `get_pressure()`. Está en el grupo `coolant_source`.
- `core_v2/systems/cryo/CoolantFlowAdapter.gd` — lee el grafo OCLS, las válvulas y el tanque de
  **una rama**, y calcula el caudal. Expone `is_flow_active()`, `get_computed_intensity()`,
  `get_computed_speed()`. Está en el grupo `coolant_adapter`. Referencia sus válvulas, fugas y
  tramos por arrays de `NodePath` (`valves`, `leaks`, `pipe_runs`).
- `core_v2/systems/cryo/LeakPatchPoint.gd` — la fisura parcheable. Está en el grupo
  `gloo_patchable`. `patch_with_gloo() -> bool`, `is_patched() -> bool`,
  `gloo_patch_duration` (hoy siempre caduca), señales `patch_applied` / `patch_expired`.
- `core_v2/props/pipe/PipeManometer.gd` — calcula
  `presión = flow_intensity * tank_level * (1 - leak_factor*0.6) * max_pressure`.
  Expone `get_pressure() -> float`. Referencia su adaptador, tanque y fuga por `NodePath`.
- `core_v2/player/MultiToolGlooProjectile.gd` — al chocar, sube por los padres del collider
  buscando un nodo con `patch_with_gloo()` y lo llama. **No lo toque.**
- `core_v2/scenes/CoolantLab.gd` — la escena-laboratorio. `is_stabilized()` es la condición de
  victoria y hoy exige `is_patched()` en ambas fisuras, que caduca a los 15 s.

## Qué implementar

### 1. `CoolantLeak.gd` — despresurizar ≠ reparar

- Cerrar la válvula (`_on_valve_state_changed(false)`) **deja de llamar `seal()`**. Pasa a marcar
  el tramo como **despresurizado**: `get_leak_intensity()` baja a 0 usando la rampa de disipación
  que ya existe (`dissipate_duration`), pero **la avería persiste**.
- Reabrir la válvula con la avería sin reparar vuelve a soltar la fuga **sin pasar por `WARNING`**
  (el caño ya está roto, no hay nada que anticipar de nuevo). Esto tiene que poder repetirse las
  veces que haga falta.
- `seal()` queda reservado para la **reparación real** (la que dispara el gloo). Solo un parche
  firme termina el ciclo.
- `_has_been_sealed` deja de bloquear el re-disparo por cierre de válvula.
- Exponer si el tramo está despresurizado, para que `LeakPatchPoint` pueda consultarlo.

Elija usted si el despresurizado es un estado nuevo del `enum State` o una bandera aparte, y
**justifique la elección en un comentario**. Lo que no puede pasar es que se confunda con
`SEALED`: son cosas distintas (uno es "sin caudal", el otro es "reparado").

### 2. `CoolantTank.gd` — el drain es consecuencia de la fuga

- El tanque **deja de drenar a ritmo fijo**. Drena proporcional al refrigerante que se está
  escapando: la suma de `get_leak_intensity()` de las fugas activas asociadas, por `drain_rate`.
- Sin fugas presurizadas, el nivel no se mueve.
- `drain_rate` sigue siendo `export` y es la perilla de calibración: Sebastián la va a ajustar
  sobre la escena. Elija un default que haga el ciclo legible (que vaciar el tanque lleve del
  orden de un minuto de fuga abierta, no cinco segundos ni diez minutos).
- El tanque necesita saber qué fugas lo afectan. La forma más limpia con lo que ya hay es que el
  `CoolantFlowAdapter` de la rama, que **ya conoce el tanque y las fugas**, le informe cuánto
  está escapando. Si toma ese camino, agregue al adaptador lo mínimo para hacerlo. No invente un
  registro global ni un autoload.
- Tanque en 0 **no mata ni daña al jugador**: es un estado de fracaso legible, no letal. Regla de
  diseño del sistema (FD-256: "ciega, no daña"). Sin caudal, manómetros en cero, y listo.

### 3. `LeakPatchPoint.gd` — parche firme vs provisorio

`patch_with_gloo()` consulta la presión del tramo **en el momento del disparo**:

- **Sin presión** (por debajo de un umbral nuevo exportado, ej. `firm_patch_pressure_threshold`)
  ⇒ parche **firme**: no caduca, la fuga queda reparada de verdad (ahí sí, `seal()`).
- **Con presión** ⇒ parche **provisorio**: dura `gloo_patch_duration` y salta, exactamente como
  hoy.

`is_patched()` y las señales `patch_applied` / `patch_expired` **no cambian de forma**. Agregue lo
necesario para distinguir firme de provisorio (por ejemplo `is_firmly_patched()`), sin romper a
quien ya los usa.

De dónde sale la presión: lo natural es el manómetro o el adaptador de la rama, que ya la
calculan. Agregue el `NodePath` que necesite. **No duplique la fórmula de presión** — pídasela a
quien ya la tiene.

### 4. `CoolantLab.gd` — victoria con cierre

`is_stabilized()` deja de exigir un parche que caduca. Estabilizado =

- ambas ramas con flujo activo,
- sin fugas activas,
- tanques por encima de un umbral.

Un parche firme lo sostiene indefinidamente; uno provisorio lo pierde cuando salta. **El puzle
tiene que poder terminarse.**

El texto del label de estado ya existe y está en español neutro; manténgalo en ese registro.

### 5. Tests

- Actualizar `core_v2/tests/test_coolant_leak.gd` y `core_v2/tests/test_coolant_circuit_flow.gd`
  a la semántica nueva. Ojo: hay tests que hoy afirman que cerrar la válvula sella —
  esos **tienen que cambiar de expectativa**, es justamente lo que se está corrigiendo.
- Nuevo `core_v2/tests/test_coolant_puzzle_loop.gd` (GdUnit3, mismo estilo que los de al lado)
  cubriendo el ciclo completo:
  1. Cerrar la válvula con fuga activa ⇒ intensidad baja a 0 con rampa, pero el estado NO vuelve
     a `HEALTHY`. Reabrir ⇒ vuelve a soltar sin pasar por `WARNING`.
  2. Con fuga presurizada el tanque baja; al cerrar la válvula deja de bajar.
  3. Gloo sobre tramo presurizado ⇒ el parche salta a los `gloo_patch_duration` segundos.
  4. Gloo sobre tramo despresurizado ⇒ el parche no caduca; reabrir deja flujo normal sin fuga.
  5. Ciclo completo en ambas ramas ⇒ `is_stabilized()` true, y **se mantiene** (no se deshace).
  6. Determinismo: snapshot a mitad de ciclo, restaurar, mismos ticks ⇒ mismo estado.

Correr la suite con:

```bash
./runtest.sh -a ./core_v2/tests/test_coolant_puzzle_loop.gd
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd
./runtest.sh -a ./core_v2/tests/test_coolant_circuit_flow.gd
./runtest.sh -a ./core_v2/tests/test_coolant_lab.gd
```

Las cuatro tienen que quedar en verde. `test_coolant_lab.gd` **no se toca**: si se rompe, es señal
de que rompió el laboratorio, no de que el test esté mal.

## Archivos permitidos

- `core_v2/systems/cryo/CoolantLeak.gd`
- `core_v2/systems/cryo/LeakPatchPoint.gd`
- `core_v2/systems/cryo/CoolantFlowAdapter.gd`
- `core_v2/props/pipe/CoolantTank.gd`
- `core_v2/scenes/CoolantLab.gd`
- `core_v2/tests/test_coolant_leak.gd`
- `core_v2/tests/test_coolant_circuit_flow.gd`
- `core_v2/tests/test_coolant_puzzle_loop.gd` (nuevo)

## Archivos prohibidos

- **`core_v2/scenes/CoolantLab.tscn`** — la escena ya está verificada y los valores exportados los
  calibra Sebastián. Si su cambio necesita un valor distinto en la escena, **dígalo en el PR**; no
  lo edite.
- `core_v2/tests/test_coolant_lab.gd` — es el test de aceptación del laboratorio.
- `core_v2/player/MultiToolGlooProjectile.gd`, `core_v2/props/pipe/PipeValve.gd`
- Cualquier escena de nivel (`core_v2/levels/**`), en especial `Dome_Intro.tscn`
- `core_v2/systems/pipe/**` y `core_v2/systems/circuit/**` — son de otra tarea en paralelo
  (FD-267). Tocarlos genera conflicto.

## Qué NO hacer

- No crear autoloads, singletons ni registros globales.
- No introducir aleatoriedad ni nada dependiente de framerate en la lógica de estado.
- No agregar daño al jugador por refrigerante: el coolant **ciega, no daña**.
- No refactorizar de más: es un cambio de semántica sobre sistemas que ya andan, no una
  reescritura. Cambios chicos y justificados.
- No tocar geometría, materiales, shaders ni partículas.

## Al terminar

**Publique el Pull Request** contra la rama de trabajo indicada, con un resumen de qué semántica
cambió y qué tests lo cubren. Si algún test viejo cambió de expectativa, dígalo explícitamente y
por qué. Si algo del brief resultó imposible o ambiguo, dígalo en el PR en vez de adivinar.
