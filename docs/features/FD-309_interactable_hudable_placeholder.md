# FD-309: Placeholder hudable de interactables inertes (criopods y airlocks de `Dome_Intro`)

**Status:** Design
**Priority:** P2
**Effort:** Medium
**Created:** 2026-09-19
**Completed:** -
**Parent:** FD-296 (OdiseaOS) · FD-297 (transiciones seamless)
**Relacionadas:** FD-307 (criocápsulas interactuables — **este FD no la reemplaza**) · FD-304 §10 (roster agregado de cápsulas) · FD-306 (radial: orden por relevancia, drawer)

## Problem

`Dome_Intro` está lleno de objetos que **se ven interactuables y no lo son**:
criopods bakeados por `DomeIntro_CriopodsSource.tscn`, airlocks, paneles de
casco. El jugador les apunta, **no pasa nada**, y el contrato visual del juego
—"si brilla, se toca; si se toca, responde"— se rompe. Un interactuable mudo no
es neutral: enseña al jugador a ignorar el sistema entero.

Hoy no existe un modo barato de declarar "este prop ya es parte de OdiseaOS,
aunque todavía no tenga contenido". Cada interactuable con pantalla se escribe a
mano (`CryoDiagnosticsUI`, `SystemStatusScreen`, `FlashlightScreen`…), y ninguno
de los props inertes tiene `HUDableComponent`, ni `InteractableEntity`, ni
marcador.

Lo que se pide: un **placeholder hudable** que se pueda colocar en cualquier
interactuable inerte para que (a) tenga marcador y ritual de interacción, (b)
aparezca en el HUD con una ficha mínima honesta ("SIN DATOS"), y (c) se pueda
**promover después** cuando llegue el contenido real — `FD-307` para las
cápsulas con ocupante, lo que venga para los airlocks.

**Fuera de alcance por decisión de Sebastian (2026-09-19):** el placeholder
**no es swappable en runtime**. No hay sustitución de asset en vivo; la
promoción es de autoría (editar la escena y hornear de nuevo).

### El problema real no es el placeholder: es el radial

Un placeholder es barato. El riesgo está en **dónde aparece**. Hoy el radial se
llena con `suit_os.get_registered_screens()` (`HudModeOverlay.gd:141`) — **todo
lo registrado se lista**. Ese es exactamente el hueco que FD-306 §2 ya tiene
identificado y pendiente, y este FD lo agrava:

- `DomeIntro_CriopodsSource.tscn` bakea **174 criopods** (`Item_0..Item_39` × 6
  clusters `Criopods2..Criopods6` por `RadialScatter`, 40 pedidos por cluster;
  IDs 12/13/19/20/26 ya no existen en los clusters 2/3/4/5/6).
- Si cada prop inerte registra su pantalla, **el radial pasa de dial a volcado**
  de ~180 entradas. No es un detalle estético: es el sistema dejando de ser
  usable.

**Regla de diseño de este FD: una entrada de registry por zona de interacción,
nunca por prop.**

| Qué | Registry | Radial | Contenido |
|---|---|---|---|
| Prop inerte (criopod vacío, airlock) | hereda la entrada de su grupo | sub-ficha del roster | "SIN DATOS" honesto |
| Prop con contenido (FD-307) | pantalla propia `ship:cryopod:pod_07` | entrada propia | ficha del ocupante |

## Solution

### 1. `InteractableStubHUDable.gd` — el placeholder (Paso 1)

`core_v2/components/InteractableStubHUDable.gd`, `extends HUDableComponent`.

Mínimo, sin lógica de mundo:

- `hud_screen_id` = `"ship:stub:<stub_id>"`. **El `stub_id` lo asigna el autor y
  es único por zona**, no por prop.
- `hud_screen_title` = `"SIN DATOS"` por defecto; el autor lo sobreescribe
  (`"PANEL DE MANTENIMIENTO"`, `"ESCLUSA 3"`…). Con `hud_screen_icon` ya entra
  al drawer de FD-305.
- `hud_view_scene` / `hud_widget_scene` = `null`. **La vista placeholder sale
  gratis**: `HudModeOverlay._show_screen()` cae al widget ampliado por
  `HudViewMount` cuando `view_scene()` es null y el snapshot no lo pide. No se
  escribe UI nueva.
- `default_relevance` = **`0.0`** (el valor por defecto del componente ya sirve).
  Una pantalla sin datos **no debe competir** en el orden por relevancia que
  pide FD-306 §2. Regla dura: el placeholder nunca se auto-promueve.
- `allowed_actions_list = []`. `perform_action()` devuelve el error existente
  `Action '<op>' not supported`. **El placeholder no finge capacidades.**

`widget_snapshot()` (JSON-safe, con el override necesario para que la UI sea
honesta en vez de vacía):

```
{
  proto: 1,
  id: "ship:stub:dome_intro_pods_a",
  title: "PANEL DE MANTENIMIENTO",
  body: "TERMINAL SIN DATOS",       # l10n: FD-303, no literal
  status: "offline",                # mismo vocabulario que _pinned_snapshot()
  source: "online"
}
```

### 2. Cómo se coloca en un prop inerte (Paso 1)

Dos piezas, ambas ya existentes, ninguna nueva:

- `InteractableEntity` (`core_v2/components/shared/InteractableEntity.gd`) — el
  `Area` que da marcador y ritual. `hudable_component_path` o el escaneo de
  hijos ya lo encuentran (`_setup_hudable()`).
- `MarkerConfig` (`core_v2/components/shared/MarkerConfig.gd`) — `label`,
  `hint`, `interaction_range`, `priority`. Un prop inerte puede tener `priority`
  bajo y `label = "SCAN"` sin mentir: el jugador recibe respuesta.

Referencia: `DomeIntroCryoDiagnosticsDisplay.tscn`, que ya monta
`InteractableEntity` + terminal + `FocusedRig` en producción.

**Costo:** una instancia por zona. Colocar `InteractableEntity` +
`InteractableStubHUDable` en **cada uno de los 174 criopods** sería cometer el
error de §"El problema real". La colocación masiva va por **grupo de scatter**
(Paso 2), no por prop.

### 3. Anti-rot: los IDs de `RadialScatter` no son estables

`RadialScatter` nombra lo bakeado `Item_%d` por **índice de emisión**
(`RadialScatter.gd:455`), y los índices ya saltan (12/13/19/20/26 faltan en
varios clusters). Con `item_count = 40`, `radius = 8.0`,
`blocked_angle_ranges_deg` por cluster, **re-bakear puede reordenar o perder
items**. Un `stub_id` derivado del nombre de nodo se rompe al re-hornear, y un
replay viejo apunta a una pantalla que ya no existe.

Regla: **el `stub_id` se ancla a un `Position3D` con `spawn_id` estable** (el
mismo mecanismo que ya usa `SceneManager._find_spawn_point`,
`SceneManager.gd:706`; `_apply_spawn_and_state` acepta
`target_spawn_id`/`spawn_id`). El autor coloca 6 anclas (una por cluster),
nombradas por zona — `crio_bay_a`..`crio_bay_f` — y el placeholder se cuelga de
la ancla, no del `Item_NN`. Los props no necesitan identidad individual para
esta feature; **si algún día un prop individual la necesita, ese es el momento
de FD-307, no de este FD.**

### 4. Roster de zona (Paso 2 — cuando el Paso 1 esté probado)

Una **sola** pantalla real por zona que agrega los placeholders y da las
sub-fichas. Ya está descrita, dos veces:

- `FD-304 §10` especifica `CryoPodsHUDable.gd` con
  `hud_screen_id = "ship:cryopods"`, `relevance()` baja y subida por alarma,
  `allowed_actions_list = ["scan", "select"]`, y `hud_view_scene =
  CryoPodsView.tscn` reusando `CryoDiagnosticsUI`.
- `FD-307 §0` mueve a ese FD la navegación **por cápsula individual** y deja a
  `FD-304 §10` como la pantalla agregada de sala.

Este FD **no duplica ni reescribe** esas dos: aporta el catálogo de sub-fichas
placeholder (los `InteractableStubHUDable` de §1) como las entradas del roster.
**Paso 2 no tiene trabajo nuevo de diseño; tiene el trabajo ya especificado en
FD-304 §10, consumido desde acá.**

### 5. Promoción: el gate de autoría (Paso 3)

Cuando un interactuable recibe su asset real:

1. Se escribe el componente real (`CryoPodHUDable.gd` de FD-307, o el que toque)
   con su **propio** `hud_screen_id` (`ship:cryopod:pod_07`).
2. El `InteractableStubHUDable` de la zona se **edita en la escena** — se
   desactiva (`enabled = false` o se borra el nodo) o se re-apunta al ancla que
   ya no tiene asset.
3. Se re-hornea la zona (`Dome_Intro.lmbake` y los `_baked.mesh` viven en repo;
   el pipeline de bake está en `tools/bake_dome_intro_criopods.gd`).

No hay swap en vivo, no hay mutación del árbol a mitad de simulación, **no hay
problema de determinismo**: la promoción es un cambio de escena como cualquier
otro, y entra al replay como parte de la carga del nivel.

**Deuda aceptada y explícita:** promocionar es trabajo de autoría manual. Si
`Dome_Intro` acumula 20 promociones, va a doler. Va al backlog como
`AutoStubResolver` (resolver el ID más específico registrado al hornear, o al
cargar la escena, nunca en gameplay) — **no se diseña acá**.

## Considered Options

- **Placeholder = convención de autoría sobre `HUDableComponent` (elegida).**
  Cero código nuevo de cámara, de viewport o de UI. Reusa `InteractableEntity`,
  `MarkerConfig`, `HudViewMount` y el fallback de widget que ya existen.
- **Placeholder swappable en runtime (gate que monta el asset real cuando el
  jugador interactúa).** Descartada por Sebastian (2026-09-19): mete el swap en
  el stream de simulación (replay/determinismo) a cambio de nada que el Paso 1
  no resuelva. Si se retoma, va como FD propio.
- **Una pantalla por prop inerte (174 registros).** Descartada: revienta el
  radial (ver "El problema real") y no aporta nada al jugador, que no puede
  distinguir la cápsula 87 de la 88.
- **No hacer nada hasta tener contenido real para cada prop.** Descartada: deja
  los props mudos justo en la zona más densa del Acto I (`Dome_Intro`), que es
  donde el contrato visual se aprende.

## Files to Modify

**Paso 1 — placeholder mínimo (implementable ya):**

- `core_v2/components/InteractableStubHUDable.gd` — **nuevo** (§1).
- `core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn` — **modificar**:
  anclas `Position3D` con `spawn_id` por cluster (§3) + un
  `InteractableEntity` + `InteractableStubHUDable` por ancla, **una por zona**.
- `core_v2/levels/interiors/Dome_Intro.tscn` — **modificar**: lo mismo para los
  airlocks/hangares inertes de la intro, un placeholder por acceso.
- `core_v2/tests/test_interactable_stub_hudable.gd` — **nuevo**: snapshot
  honesto (`body`/`status`), `default_relevance == 0.0`, `allowed_actions()`
  vacío, `perform_action()` falla limpio, `screen_id` estable tras re-bake.
- `docs/features/FEATURE_INDEX.md` — alta de FD-309.

**Paso 2 — roster de zona:** sin archivos nuevos acá; es FD-304 §10
(`CryoPodsHUDable.gd` + `CryoPodsView.tscn`).

**Paso 3 — promoción:** sin archivos acá; cada promoción vive en su FD
(FD-307 para cápsulas con ocupante).

## Verification

1. **Ya no hay mudos.** Acercarse a un cluster de criopods y a un airlock en
   `Dome_Intro` muestra marcador y responde a la interacción.
2. **Honestidad.** La pantalla dice "SIN DATOS" y **no ofrece acciones**: ningún
   botón que no haga nada, ningún "ejecutar" que no ejecute.
3. **El radial no explota.** Con la zona completa cargada, el conteo de
   `get_registered_screens()` **no crece con la cantidad de props**: 6 anclas de
   criopods aportan 6 entradas (o 1 si el roster del Paso 2 ya está), no 174.
   Este es el criterio que decide si el FD está bien o mal.
4. **Relevancia.** Un placeholder nunca desplaza a `FlashlightScreen` ni a
   `SystemStatusScreen` en el orden por relevancia (FD-306 §2); su
   `relevance()` es `0.0` y no sube con nada.
5. **Estabilidad de ID.** Re-hornear `DomeIntro_CriopodsSource` (`rebuild_baked_items
   = true`) deja los `stub_id` intactos: los anclajes son `Position3D` con
   `spawn_id`, no `Item_NN`.
6. **Promoción limpia.** Al reemplazar un placeholder por su componente real
   (simulado con FD-307 sobre una cápsula), la zona queda con **una** entrada
   para ese prop y **cero** placeholders huérfanos apuntando a él.

## Fuera de scope

- Swap en runtime del placeholder por el asset real (decisión de Sebastian,
  2026-09-19).
- `AutoStubResolver` (backlog; ver §5).
- Navegación por cápsula individual — es FD-307.
- El roster agregado en sí — es FD-304 §10; este FD solo lo consume.
- Acto II: abrir, despertar, expulsar.
