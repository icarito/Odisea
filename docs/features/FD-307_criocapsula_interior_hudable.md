# FD-307: Criocápsulas interactuables — cámara fija interior + holoterminal del ocupante

**Status:** Design
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-19
**Completed:** -
**Parent:** FD-296 (OdiseaOS) · FD-296 F4 (RemoteHUD) · FD-304 (interfaz diégetica con gamepad)
**Relacionadas:** FD-307 depende de FD-296 F1 (contrato `HUDableComponent`). Convive con FD-304 §10 (ver §0).

## Problem

Las criocápsulas son hoy **puro decorado**. Existen dos variantes modeladas:

| Escena | Qué trae | Dónde se usa |
|--------|----------|--------------|
| `core_v2/props/criopod/Criopod_vert.tscn` | Pod completo: `RotatingObjectV2` (la escotilla gira, `InteractableBaseV2`, ya en `replay_sync`), 6 `CollisionShape`, `SFX Open sound`, `Smoke`, `Sparks` | `RingHub_Level.tscn`, `test_replay_prop_snapshots.gd` |
| `core_v2/props/criopod/CriopodParallax.tscn` | Versión parallax: nodo `Interior`, `Glass`, **`PersonCard2`** (tarjeta de ocupante) | `Dome_Crio.tscn`, `Dome_Intro_Fire.tscn`, `DomeIntro_CriopodsSource.tscn` |

Ninguna tiene componente HUDable, ni datos de ocupante, ni una vista. El jugador
que despierta de la suya no puede volver a mirarla, y las otras 27 son cajas
cerradas: el mayor objeto narrativo de la criogenia —*¿quién venía conmigo?*— no
se puede usar.

Lo que pides: **entrar a la cápsula con una cámara fija y ver una holoterminal
dentro**. Y que aplique a la de Elías **y a todas**.

## Solution

### 0. Relación con FD-304 §10 (importante)

FD-304 §10 especifica un `CryoPodsHUDable.gd` montado **una sola vez** sobre la
bahía, agregando todas las cápsulas en **una** pantalla de roster/diagnóstico que
reusa `CryoDiagnosticsUI` (que es telemetría de sala: coolant, válvulas, fugas).

Eso **no es esto**, y no se pisa:

| | FD-304 §10 | FD-307 (este FD) |
|---|---|---|
| Alcance | 1 pantalla agregada del barco | 1 vista por cápsula |
| Contenido | Diagnóstico de sala/coolant | Ficha del **ocupante** |
| Cámara | La del `HangingDisplay` (fuera) | **Fija dentro de la cápsula** |
| Fuente de datos | `RoomDialsPanel` (mundo) | Estado del pod (estático + alarma) |

**Se mueve el "una sola instancia" de FD-304 §10 a este FD**: §10 queda como la
pantalla de diagnóstico agregada (correcta tal cual), y la navegación por cápsula
individual vive acá. Pendiente: anotar la referencia cruzada en FD-304 §10 al
implementar (una línea).

### 0.1 Decisión (2026-09-19, Sebastián) — cada cápsula es su propio HUDable

Corrección sobre lo implementado en FD-304 §10: **no** hay una pantalla agregada
"Criocápsulas" como identidad de las cápsulas. **Cada cápsula es su propio
HUDable, y solo mientras es interactuable**: al mirarla aparece su widget de
contexto (FD-310) y al activarla se abre su vista (`ship:cryopod:<pod_id>`). No
se registran 28 `Pod_NN` en el radial, y no hay un roster "Criocápsulas" que las
represente a todas.

Consecuencias de diseño:

- El HUDable de una cápsula se ofrece **mientras el jugador la tiene como
  interactuable en rango** (el `best_target` de `PlayerControllerV2`), no de
  forma permanente. El registro/visibilidad de esa pantalla es dinámico y sigue
  el ciclo de interacción (FD-310).
- `CryoPodsHUDable.gd` (`ship:cryopods`, implementado en FD-304 §10) queda
  **deprecado** para las cápsulas: se retira cuando entre `CryoPodHUDable`.
  Su telemetría de sala (coolant) no se pierde: es del `ShipSystemBus`, que ya
  tiene su propia pantalla de Sistemas de nave.
- Esto resuelve la Open Question 3 de abajo (no hay que elegir entre "todas" y
  "una vista re-apuntada": todas se ofrecen, pero de a una, la que se mira).

### 1. No hay que inventar cámara: el patrón ya existe

`core_v2/levels/interiors/DomeIntroCryoDiagnosticsDisplay.tscn` es exactamente la
forma que pides, ya en producción:

```
HangingDisplay (WallTerminal.tscn)
├── ScreenContainer/ScreenMesh      ← quad con shader HoloScreen
├── Viewport (1280×816)             ← la UI vive acá
│   └── CryoDiagnosticsUI
├── InteractableEntity              ← el Area que el jugador activa
└── CinematicSetup
    ├── CameraZone (Area)           ← entra/sale al acercarse
    ├── CinematicPathRig            ← (no se usa en modo foco)
    └── FocusedRig                  ← transform fijo + transition_time = 1.5
        └── Camera
```

`HoloTerminalHUDable.gd` ya sabe exponerlo: `view_transition_origin()` devuelve
`{"kind": "focus_rig", "path": ...}` y `HudModeOverlay._show_screen()` (línea ~796)
lo detecta y entra al modo foco sin código nuevo. **La cámara fija es gratis**:
el `FocusedRig` no se mueve mientras está enfocado.

**Matiz que hay que respetar:** el radial del ascensor
(`ElevatorFloorSelector.gd`) deliberadamente **no** mueve la cámara. Esto es lo
contrario: sí hay corte a una cámara fija, como el `HangingDisplay`. Si lo que
quieres es *sin corte* (la holoterminal proyectada donde ya estás parado), el
diseño cambia por completo — ver Open Question 1.

### 2. Escena nueva: el interior de la cápsula

`core_v2/props/criopod/CryoPodInterior.tscn` — **nueva**, basada en
`WallTerminal.tscn`, montada **dentro** del pod:

- `FocusedRig` con transform fijo **dentro** de la cápsula (mirada al panel de
  techo/lateral), `transition_time` ~1.2–1.5 s (el del `HangingDisplay` es 1.5).
- `Viewport` + la UI del ocupante (§4).
- `CameraZone` ajustada al volumen del pod, no a una sala.
- `ScreenMesh`/`ProjectorMesh` reusados tal cual: la holoterminal se ve como una
  proyección sobre vidrio, que es el lenguaje visual que ya tiene el juego.

**Reuso, no duplicado:** el interior se instancia **una vez por cápsula
interactuable** (§6), no 28 veces en la escena de la bahía.

### 3. El componente: `CryoPodHUDable.gd`

`extends HoloTerminalHUDable` (no `HUDableComponent` directo): hereda toda la
maquinaria de terminal, foco, viewport y snapshot remoto, y solo agrega lo del
pod. `HoloTerminalHUDable` ya está pensado para esto — expone un
`HoloTerminalV2`/`WallTerminal` como pantalla sin tocarlo.

- `hud_screen_id` = `"ship:cryopod:<pod_id>"` — **único por cápsula**. Es la
  clave del registry, del pin a slots y del `open_screen(id)` remoto.
- `hud_screen_title` = el nombre del ocupante si lo tiene, si no `"CRIOCÁPSULA
  <n>"`. Es lo que se lee en el radial; un roster de 28 "CRIOCÁPSULA" sería
  inútil (ver Open Question 2).
- `hud_view_scene` = `CryoPodView.tscn` (nueva): el panel del ocupante.
- `hud_widget_scene` = `CryoPodWidget.tscn` (nuevo): versión compacta para el
  slot/widget, sin cámara.
- `default_relevance` baja (una cápsula dormida no compite con la linterna), y
  sube **fuerte con alarma** — mismo patrón que `SystemStatusScreen` con
  `STATE_FALLO`, y el mismo que FD-304 §10 ya prevé.

### 4. Qué muestra la holoterminal

`widget_snapshot()` (JSON-safe, mismo contrato que el resto del HUD):

```
{
  pod_id: "pod_07",
  title: "CRIOCÁPSULA 07",
  occupant: { name, role, status },     # null si está vacía
  hibernation: { elapsed_days, integrity_pct, coolant_ok },
  alarm: bool,
  door: { open: bool, angle: float },   # del RotatingObjectV2, ya en replay_sync
  source: "online"
}
```

Regla dura: **la ficha es de lectura en MVP.** Ver y entender, no operar. Abrir
la escotilla, despertar a alguien o expulsar la cápsula son **Acto II** (coincide
con FD-304 §10, que ya difiere `eject`/`wake`).

### 5. Cómo se entra

El acceso es **desde afuera, por interacción**, igual que la `HangingDisplay`:

1. El jugador mira/se acerca a una cápsula → el prompt de interacción aparece
   (mecanismo existente de `InteractableBaseV2`).
2. Activa → `FocusedRig` corta a la cámara interior (1.2–1.5 s) y la holoterminal
   se enciende.
3. La UI queda navegable con mouse, gamepad y touch.
4. Salir devuelve la cámara al jugador.

**No hay navegación del jugador dentro del pod.** No se camina adentro: se mira
desde el pasillo y la cámara entra. Meter movimiento 3D dentro de un cilindro de
~1 m es otro sistema (colisiones, cámara en espacio cerrado) y no aporta nada a
lo que el objeto tiene que decir.

### 6. Cuántas cápsulas (el problema real)

Hay **dos costos** por cápsula interactuable: un `Viewport` (memoria de render
target) y una `Camera`. Con 28 cápsulas eso es inaceptable, y además la mayoría
está vacía.

**Diseño propuesto: una sola vista interior, montada en la cápsula que el jugador
está mirando.** El `FocusedRig` y el `Viewport` viven en **una** escena
`CryoPodInterior.tscn` que se re-parenta (o se re-posiciona) al pod enfocado, y
`CryoPodHUDable` se re-apunta al pod actual antes de abrir. Esto da "todas las
cápsulas son interactuables" con el costo de una.

Variante más simple si la anterior da problemas: un `CryoPodHUDable` por cápsula
**con datos** (una docena) y cápsulas vacías no interactuables. Ver Open
Question 3 — es la decisión que define el tamaño del FD.

### 7. Determinismo

- Entrar y salir de la vista fija es una **acción de gameplay** (`interact`) que
  ya entra al stream; el estado de la escotilla (`RotatingObjectV2`) ya está en
  `replay_sync` y tiene `get_snapshot()` (verificado en
  `test_replay_prop_snapshots.gd`).
- Los **datos del ocupante** son estáticos de diseño (no simulan), así que el
  replay los reproduce por `pod_id` sin estado extra.
- El `FocusedRig` es presentación pura: no decide nada. Un replay que abre la
  vista interior no puede divergir por culpa de la cámara.

### 8. Lo que NO entra

- **Abrir la escotilla desde la terminal** (`door.open`) — Acto II.
- **Despertar / expulsar ocupantes** (`wake`, `eject`) — Acto II (ya diferido en
  FD-304 §10).
- Modelo de simulación de hibernación (días, integridad): la ficha **lee** valores
  de diseño, no los simula. Si más adelante hay simulación, esta ficha es su
  primera consumidora.
- La cápsula de Elías como **cinemática de despertar** — es otra cosa (intro), no
  esta vista.

## Considered Options

- **Reusar el patrón `FocusedRig` + `WallTerminal` (elegida).** Ya existe, ya está
  en producción en el `HangingDisplay`, y `HoloTerminalHUDable` ya lo expone al
  HUD. Costo de cámara y de viewport: cero código nuevo de cámara.
- **Reusar `CryoDiagnosticsUI` para el contenido.** Descartada: esa UI es
  telemetría de sala (coolant, válvulas, fugas), no ficha de ocupante. Comparten
  contenedor, no contenido.
- **Sin corte de cámara** (la holoterminal, como el radial del ascensor). Es más
  barato pero pierde el "dentro de la cápsula": desde afuera no se ve el interior
  de un pod cerrado. Ver Open Question 1.
- **Navegación del jugador dentro del pod.** Descartada (§5).
- **Un `Viewport`+`Camera` por cápsula.** Descartada por costo (§6).

## Fuera de scope

- Acto II: abrir, despertar, expulsar.
- Simulación de hibernación.
- Cinemática de despertar de Elías.
- Vista 2D/parallax dedicada (las cápsulas parallax no cambian).

## Files to Modify

- `core_v2/props/criopod/CryoPodInterior.tscn` — **nuevo** (§2, base
  `WallTerminal.tscn`).
- `core_v2/props/criopod/CryoPodView.tscn` — **nuevo** (panel del ocupante).
- `core_v2/props/criopod/CryoPodWidget.tscn` — **nuevo** (widget de slot).
- `core_v2/components/CryoPodHUDable.gd` — **nuevo** (§3, `extends
  HoloTerminalHUDable`).
- `core_v2/props/criopod/Criopod_vert.tscn` — montar el `InteractableEntity`/zona
  del interior (modificar, sin tocar el `RotatingObjectV2` ni las colisiones).
- `core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn` — instanciar el
  componente sobre la bahía (modificar).
- `docs/features/FD-304_hud_gamepad_diegetico.md` — nota de referencia cruzada en
  §10 (modificar).
- `core_v2/tests/test_cryopod_hudable.gd` — **nuevo**: snapshot con/sin ocupante,
  `pod_id` único, relevancia con alarma, roundtrip remoto.
- `docs/features/FEATURE_INDEX.md` — alta de FD-307 (modificar).

## Verification

1. **Cámara fija.** Activar una cápsula corta al `FocusedRig` interior
   (~1.2–1.5 s) y **no se mueve** mientras dura el foco. Salir devuelve la cámara
   al jugador.
2. **Holoterminal legible.** El panel se ve nítido dentro del pod
   (`hold_full_resolution_ui`, ya usado por el HUD) y usa el shader `HoloScreen`.
3. **Ficha.** Con ocupante muestra nombre/rol/estado; vacía muestra el estado
   vacío sin romper.
4. **`pod_id` único.** Dos cápsulas distintas abren dos pantallas distintas en el
   registry de `SuitOS`; no colisionan en `pinned_slots`.
5. **Relevancia.** Una cápsula en alarma sube su `relevance()` por encima de las
   dormidas.
6. **Costo acotado (§6).** Abrir la bahía completa **no** crea 28 viewports; el
   conteo de `Viewport` vivos no crece con la cantidad de cápsulas.
7. **Deck.** Las cápsulas parallax (`CriopodParallax`) siguen funcionando como
   decorado, sin interactuable y sin costo.
8. **Replay.** Un replay que entra y sale de la vista reproduce la secuencia sin
   divergir, con la escotilla en `replay_sync`.
9. **Gamepad.** Con FD-304, la ficha responde a `hud_gamepad_actions()` (A/X) o
   cae al camino de foco de la GUI.

## Open Questions

1. **¿Hay corte de cámara o no?** Esto especifica **sí** (corte a una cámara fija
   interior, como el `HangingDisplay`). El radial del ascensor es el patrón
   opuesto: no mueve la cámara. Pides "cámara fija dentro de la cápsula", y eso
   solo se puede si la cámara entra. **Confirmar.**
2. **Título de cada cápsula.** ¿Se llama por el ocupante (`"CRIOCÁPSULA — ELÍAS"`)
   o por número (`"CRIOCÁPSULA 07"`)? Afecta lo que se lee en el radial y en el
   roster. ¿Y las vacías?
3. **Cuántas son interactuables (§6).** ¿Todas (→ vista única re-apuntada) o solo
   las que tienen ocupante con datos (→ una instancia cada una)? Define el
   tamaño del FD.
4. **¿La de Elías es distinta?** Pides "la de Elías y todas". ¿La suya tiene algo
   propio (por ejemplo, es la que se abre en la intro) o es una más?
