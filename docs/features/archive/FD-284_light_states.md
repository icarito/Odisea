# FD-284: Estados de iluminación del domo

**Status:** In Progress
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-08-31
**Completed:** -

## Problem

El domo se ilumina con un lightmap horneado (`Dome_Intro.lmbake`, ~56 MB) más un
pool runtime de luces cercanas al jugador (`LightPathV2` + `MobileLightBudget`),
recortado para que el Adreno 618 no se ahogue en fillrate. Es un solo look: no hay
forma de mostrar el domo a oscuras, ni de mostrarlo plenamente encendido sin pagar
luces en tiempo real.

Hacen falta tres estados, y en móvil no se puede pagar el precio de tenerlos todos
cargados a la vez.

## Solution

Tres estados en un autoload, con un `.lmbake` por modo y el pool runtime como la
única palanca de tiempo real:

| Estado | Bake | Pool runtime |
|---|---|---|
| `OSCURAS` | `dark` | 0 |
| `BAJO` | `dark` | tamaño original (comportamiento previo, intacto) |
| `PLENO` | `full` | 0 |

`BAJO` es el default: arrancar en otro estado cambiaría el look actual del domo sin
que nadie lo haya pedido.

Los bakes viven en `res://core_v2/levels/interiors/lightmaps/<modo>/<Escena>.lmbake`.
Una carpeta por modo es obligatoria, no cosmética: con `atlas_generate = false`
BakedLightmap escribe un PNG por MeshInstance junto al `.lmbake`, y los nombres se
repiten entre modos.

El bake histórico `core_v2/levels/interiors/Dome_Intro.lmbake` **no se toca**: sigue
siendo el que la escena referencia y queda como respaldo.

### Considered Options

- **Opción A — un `.lmbake` por estado, swap en runtime.** Pro: cada estado se ve
  como fue horneado, y solo uno está en memoria por vez. Contra: hay que hornear dos
  veces y el `.lmbake` oscuro suma peso al paquete (mitigado con
  `default_texels_per_unit = 4` y `quality = LOW`, que es donde el modo oscuro no
  tiene detalle que perder).
- **Opción B — un solo bake y modular la energía en runtime.** Pro: cero peso extra.
  Contra: oscurecer un bake claro no apaga los fixtures, solo los atenúa; y aclarar
  el oscuro no inventa la luz rebotada que nunca se horneó.
- **Seleccionada: A.** El objetivo es visual, y B no puede producir el estado PLENO
  (todos los fixtures encendidos) partiendo de un bake que nunca los tuvo. La
  restricción de iOS ("nunca los dos bakes en memoria") se resuelve soltando la
  referencia vieja antes de pedir la nueva, no evitando el segundo bake.

### Nombre del bake: parametrizado, no hardcodeado

`Dome_Prologue.tscn` **es otra escena**: instancia `Dome_Base.tscn` (de donde salen
los pools de luces, que Dome_Intro también instancia) con
`Environment_InteriorLab.tres`, y **no tiene nodo `BakedLightmap` ni `.lmbake`
propio**. Por eso ni el autoload ni el script de bake fijan "Dome_Intro": el nombre
sale del nodo raíz de la escena activa.

En Dome_Prologue, entonces, el swap de bake es un no-op y los tres estados quedan
diferenciados solo por el pool. Cuando gane su propio bake, alcanza con hornearlo a
`lightmaps/<modo>/Dome_Prologue.lmbake` — no hay que tocar código.

### Parpadeo

`set_flicker(depth, hz)` es una capa sobre el estado actual, no un cuarto estado: no
rehornea nada. Se apoya en el autoload `SceneLighting`, que ya sabe escalar la energía
de todas las luces y el ambiente, así que no agrega materiales, transparencias ni
post-proceso (restricción GLES2). La forma de onda son dos senos inconmensurables, sin
RNG, para no romper el replay determinista.

Techo conocido, marcado en el código: es modulación global de brillo, no un material
emisivo por fixture, y comparte `SceneLighting` con `AirlockTransitionFX`.

## Files to Modify

- `core_v2/systems/DomeLightState.gd` (nuevo) — autoload; enum, `state_changed`, swap
  de bake, control del pool, flicker, `get_snapshot()`/`restore_snapshot()`.
- `project.godot` (modify) — registro del autoload.
- `tools/generate_dome_intro_bake_lights.gd` (modify) — `--mode=full|dark|near`,
  `--scene=`, y corrección de las rutas de nodos.
- `tools/editor_bake_dome_intro_lightmap.gd` (modify) — `DOME_BAKE_MODE`, destino por
  modo/escena, ajustes de resolución del bake oscuro, restauración de `light_data`.
- `tools/postprocess_dome_intro_lightmap.sh` (modify) — documentación de los
  parámetros por modo (ya era íntegramente configurable por entorno).
- `Makefile` (modify) — reenvío de `DOME_LIGHTMAP_STAMP_DIR` / `DOME_LIGHTMAP_RAW_DIR`.
- `core_v2/levels/interiors/DomeIntro_BakeLights_dark.tscn` (nuevo, generado).
- `tools/verify_dome_intro_bake_lights.gd` (modify) — verifica también el rig oscuro.
- `tools/verify_dome_intro_runtime_light_budget.gd` (modify) — **corrección de bug
  preexistente**: buscaba los pools en la raíz de Dome_Intro, y se mudaron a
  `Dome_Base`; fallaba en `main`.
- `core_v2/tests/test_dome_light_state.gd` (nuevo).

### Sobre `mode=near`

No existe ningún filtro de cercanía en el horneado, ni existió: el
recorte "por cercanía" es el pool runtime de `LightPathV2`, que ocurre en juego. El
generador ya emitía las 107 luces. `--mode=near` queda aceptado como alias de `full`
con un aviso, y `full` reproduce el rig histórico byte a byte.

### Bug preexistente encontrado

`generate_dome_intro_bake_lights.gd` y `verify_dome_intro_runtime_light_budget.gd`
buscaban `WallLights`, `HubExitLights`, `DomeLamp` y `DomeLampCrown` en la raíz de
`Dome_Intro`. Esos nodos se mudaron a `Dome_Base` cuando se extrajo la escena base, y
las rutas nunca se actualizaron: el generador emitía cero luces (con `push_error`,
pero guardaba igual) y el verificador fallaba. Ambos corregidos, y el transform se
compone recorriendo la cadena de padres hasta la raíz del domo en vez de asumir qué
nodos están en identidad.

## Iluminación de props: lo que el bake NO cubre

Censo de `Dome_Intro` (`tools/` ad-hoc, ver historial de FD-284):

| | |
|---|---|
| `MeshInstance` en la escena | 169 |
| Con `use_in_baked_light` | 40 — todas horneadas, todas con UV2, 0 faltantes |
| Sin la marca | 129, de las cuales **128 no tienen UV2** |
| `MultiMeshInstance` | 23 — en Godot 3 **no pueden recibir lightmap** |

O sea: criopods, fixtures y señalética (que viven en MultiMesh) nunca van a recibir el
lightmap, y el resto de los props necesitaría un unwrap de UV2 antes de siquiera ser
candidato. **Marcar sombras no cambia nada**: el bake está sano, los props no son
candidatos.

Tampoco sirve el ambiente como relleno: subir `ambient_light_energy` de 0.2 a 0.9, y
después el `ambient_light_color` ×6, mueve la media del frame menos de 1 punto (45.8 →
46.3 y 43.9 → 44.7). El color ambiente del domo es casi negro.

Lo único que ilumina a los props son las luces del pool. Medido sobre el mismo frame:
`WallLights.light_energy` 0.45 → media 56.8; 1.10 → media 63.9. Ese omni hace dos
trabajos a la vez —disimular la costura con la pared horneada e iluminar los props— y
bajarlo resuelve el primero rompiendo el segundo. Quedó en **0.8** como compromiso.

### Mejora progresiva del pool

`MobileLightBudget` ahora ajusta el pool en las **dos** direcciones, no solo hacia abajo:

- Sube de a una hasta `max_pool_size` (3, el valor que el propio autoload asumía antes
  de que FD-273 lo bajara a 1) tras `pool_upgrade_seconds` (12 s) de fps sostenidos
  sobre `pool_high_fps` (50).
- **Trinquete**: la primera bajada pone `_degradado` y cancela la subida para el resto
  de la sesión. El motivo del comentario original sigue vigente —cada cambio del conteo
  recompila variantes de shader en GLES2, con tirones de 50-90 ms— así que un aparato
  que ya sufrió no vuelve a pagar recompilaciones, y nunca oscila.
- En escritorio (`_solo_subida`) no se recorta ningún rango ni se adelgaza el pool, pero
  la subida sí corre: antes el autoload salía en `_ready()` y el adaptativo no existía
  fuera de móvil.
- Un pool en 0 no se toca: es `DomeLightState` en PLENO/OSCURAS, una decisión del nivel
  y no falta de presupuesto.

`DomeLightState` refresca su baseline de pool en cada lectura no-nula, para que al salir
de PLENO devuelva el presupuesto vigente y no el que vio la primera vez.

## Verification

1. `./runtest.sh -a ./core_v2/tests/test_dome_light_state.gd` — 5 tests: cambio de
   estado + señal, swap de bake sin dos recursos vivos, presupuesto de pool por estado
   (0 en PLENO), escena sin lightmap, snapshot.
2. `godot3-bin --headless --no-window -s tools/verify_dome_intro_bake_lights.gd` — rig
   full con 107 luces desactivadas en runtime + rig dark vacío.
3. `godot3-bin --headless --no-window -s tools/verify_dome_intro_runtime_light_budget.gd`
   — 4 luces de pool en la escena horneada.
4. `./runtest.sh -a ./core_v2/tests/` — 133 tests, sin regresiones por el autoload nuevo.
5. `./runtest.sh -a ./core_v2/tests/test_light_budget_pool_ratchet.gd` — 4 tests del
   trinquete: sube hasta el techo, una bajada lo cancela, no pisa un pool en 0, no baja
   por debajo de lo autorizado.
6. Pendiente en el editor (Godot 3 solo hornea dentro del editor):
   `DOME_BAKE_MODE=dark` + `File > Run` sobre `tools/editor_bake_dome_intro_lightmap.gd`
   con `Dome_Intro.tscn` abierta, y lo mismo con `DOME_BAKE_MODE=full`. Hasta que esos
   dos `.lmbake` existan, `DomeLightState` avisa y conserva el bake de la escena.
