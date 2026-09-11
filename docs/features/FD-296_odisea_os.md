# FD-296: OdiseaOS — sistema operativo del traje (modo HUD + widgets)

**Status:** Design
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-11
**Completed:** -

## Problem

La información de los sistemas de la nave, la Multi-tool y las HoloTerminals
solo se lee en terminales físicos puntuales: al cerrarlos, el jugador pierde
el contexto de los puzzles y el estado de sus herramientas. Además, el Control
Remoto (FD-294) necesita un "modo HUD" propio y el prototipo actual
(`HelmetHUDV2` + `TerminalHUDBridge`) resuelve el acople a cámara pero no
define la **funcionalidad**: qué pantallas existen, cómo se eligen, qué se ve
en juego normal vs. modo HUD, y cómo convive con N sesiones remotas.

Esta FD **absorbe y reemplaza FD-295** (HUD persistente de sistemas): lo que
allí era "indicadores persistentes" pasa a ser una *pantalla* de OdiseaOS con
su *widget resumen*, y el patrón se generaliza a cualquier interactuable.

## Solution

**OdiseaOS = el sistema operativo del traje de Elías.** Una capa de UI
diegética, holográfica, que corre en el casco. Tiene dos modos:

1. **Modo widget (juego normal)**: 1–3 widgets compactos visibles en pantalla.
2. **Modo HUD (inmersivo)**: transición a primera persona + pausa + selector
   radial de pantallas + vista completa.

El Control Remoto (teléfono) corre **siempre en modo HUD**, pero como
**overlay en vivo sin pausa** (el juego sigue corriendo; el teléfono es mando
+ espejo). La multisesión remota queda en backlog (v1 = 1 sesión).

### Arquitectura en capas

#### 1. Núcleo: autoload `SuitOS`

- **Registro de pantallas**: cada pantalla se registra con su *vista completa*
  (para modo HUD) + *widget resumen* (compacto) + *proveedor de relevancia*.
- **Estado activo**: pantalla abierta/cerrada, slot automático, slot fijado.
- **Scorer de relevancia**: puntúa widgets según contexto y elige el widget
  automático. Reglas v1:
  - sistema en FALLO/DEGRADADO sube (criocoolant, plasma, atmósfera, energía);
  - Multi-tool en uso (láser/gloo activo) sube;
  - Tremor activo (FD-288) sube estabilidad estructural;
  - HoloTerminal cercano/abierto recientemente sube su widget.
- **Señales** (patrón EventBus): `screen_opened(id)`, `screen_closed(id)`,
  `widget_changed(slot, id)`, `haptic{kind}` (ver Vibración).

#### 2. Pantallas = módulos

Cada pantalla aporta vista completa + widget resumen. Se alimentan por
señales de los sistemas (solo lectura, sin lógica de puzzle).

**Pantallas v1:**

| Pantalla | Vista completa (modo HUD) | Widget resumen | Fuente |
|---|---|---|---|
| Sistemas de nave | Dashboard 4 sistemas (criocoolant, plasma, atmósfera, energía) con datos clave | 4 filas compactas: ícono + estado OK/DEGRADADO/FALLO + 1 dato | `ShipSystemBus` (FD-255/256/257/258/259) |
| Multi-tool | Estado completo: modo, carga, heat, munición gloo | Modo activo + carga | `MultiToolV2` (exponer estado) |
| HoloTerminals HUDables | Vista del terminal vinculado (reuso `HoloTerminalV2`) | Estado/resumen que el terminal declare | Cualquier interactuable HUDable |

#### 3. HUDables

Extender el sistema de interactuables: cualquier interactuable puede
declararse **HUDable** (análogo al `marker_config` de `InteractableEntity`):

- `HUDableComponent` (nuevo, junto a `InteractableEntity`): exporta
  `hud_view_scene` + `hud_widget_scene` + `hud_screen_id`, y se registra en
  `SuitOS` al entrar al árbol (mismo patrón register/unregister de
  `InteractionMarker`).
- Una HoloTerminal encontrada en el mundo, un sistema de la nave, o un prop
  ad hoc pueden ofrecer su pantalla sin tocar el núcleo.

#### 4. Modo HUD (local, inmersivo)

1. Jugador activa modo HUD → transición a primera persona (reuso del attach
   animado de `HelmetHUDV2`, ~0.45 s).
2. **El mundo pausa** (`get_tree().paused = true`; la UI del HUD corre con
   `pause_mode = PAUSE_MODE_PROCESS`). Decisión tomada con Sebastián: el modo
   HUD local es la consola del traje, el mundo espera — input limpio, sin
   pelea de mouse, determinismo intacto.
3. **Selector radial** de pantallas (reuso `RadialSelectorV2`: aim-driven, no
   roba cursor ni corta cámara).
4. Pantalla completa seleccionada. Puntero de mouse si hay mouse; si no,
   navegación por radial/teclas.
5. Al salir: reanuda juego + transición de regreso a tercera persona + HUD
   vuelve a modo widget.

#### 5. Slots de widgets (juego normal)

- **2 slots en v1** (decisión: empezar simple; 3+ queda abierto a futuro):
  - Slot A — **automático**: lo que el scorer considere más relevante.
  - Slot B — **fijado por el jugador**: pin desde el modo HUD.
- Los widgets **se ajustan a la pantalla** (reuso `UIScaleCompensator`).
- Se ocultan en cinemáticas y menús.
- Toggle de accesibilidad en Settings.

#### 6. Control Remoto (integración con FD-294)

- El teléfono corre **siempre en modo HUD**: vista completa de la pantalla
  activa + radial propio. Sin pausa (overlay en vivo).
- Reuso del protocolo FD-294: `scene_directive{kind:"ui"|"screen"}` para
  empujar pantallas al teléfono; `input{touch,accel,gyro}` ya definido.
- El HUD local y el remoto comparten el mismo registro de pantallas
  (`SuitOS`) pero **estado independiente** (pantalla activa remota ≠ local).
- Multisesión (varios teléfonos, cada uno independiente): **backlog**.

#### 7. Vibración / hápticos

- `SuitOS` emite eventos `haptic{kind}`; el canal remoto los traduce a
  vibración del teléfono (protocolo FD-294).
- **v1**: `haptic{tremor}` disparado por TremorZone (FD-288) cuando
  aterrice — la vibración no es una feature suelta, es la respuesta háptica
  de un evento del bus. Otros eventos hápticos: backlog.

### Contratos (F1) — datos separados de presentación

**Regla de oro:** todo lo que viaja a los slots, al modo HUD o al Control
Remoto es **data pura serializable** (JSON-safe). Ninguna pantalla expone
nodos, NodePaths ni referencias a objetos fuera de su árbol.

#### Fuente de pantalla (contrato que implementa cada HUDable)

| Miembro | Contrato |
|---|---|
| `screen_id() -> String` | Identificador único y estable entre sesiones y saves. Cambiarlo = migración explícita. |
| `screen_title() / screen_icon()` | Copy e ícono para el radial. |
| `widget_snapshot() -> Dictionary` | Estado del widget: **solo** String/int/float/bool/Array/Dictionary (Vector3 → arrays). Incluye `"proto": 1`. Snapshot completo e idempotente (no deltas en v1): el teléfono re-renderiza con cada mensaje. |
| `view_scene() -> PackedScene` | Pantalla completa para modo HUD local. |
| `widget_scene() -> PackedScene` | Widget compacto para slots locales (escala con UIScaleCompensator). |
| `relevance(context) -> float` | 0..1 para el slot automático. Función pura, determinista, sin efectos secundarios. |
| `allowed_actions() -> Array[String]` | Whitelist de operaciones. Única puerta de entrada, igual para input local y remoto. |
| `perform_action(op, args) -> Dictionary` | Valida `op` contra `allowed_actions()`; devuelve `{ok, result}` o `{ok: false, error}`. |
| señal `state_changed()` | SuitOS re-consulta `widget_snapshot()` al emitirse. |

#### SuitOS (autoload) — registro, slots, persistencia

- `register_screen(screen)` / `unregister_screen(id)`: idempotentes, mismo
  patrón register/unregister de `InteractionMarker`.
- **Slot A (automático):** fuente con mayor `relevance(context)` vigente.
  **Slot B (fijado):** `pin(screen_id)` / `unpin()` desde el modo HUD.
- **Persistencia al HUD:** el pin y el último snapshot de cada slot se guardan
  vía `PersistenceManager`. Al cargar partida, SuitOS re-resuelve por
  `screen_id`; si la fuente no existe en la escena actual, el slot muestra el
  último snapshot con `"source": "offline"` (nunca desaparece en silencio).
- Señales de salida: `screen_registered(id)`, `screen_unregistered(id)`,
  `widget_changed(slot, snapshot)`, `hud_mode_changed(active)`,
  `haptic(kind, intensity)`.
- **Solo lectura de fuentes.** Toda escritura al mundo pasa exclusivamente por
  `perform_action` de la fuente — mismo camino para input local y remoto
  (compatible con determinismo/replay: las acciones son eventos, como el
  resto del input).

#### Despliegue en dos modos (mismo contrato)

| Modo | Presentación | Datos | Entrada |
|---|---|---|---|
| Local — modo HUD | `view_scene` acoplada vía HelmetHUDV2, mundo pausado | snapshot vivo | mouse/touch + `perform_action` |
| Local — slots | `widget_scene` + UIScaleCompensator | `widget_changed(slot, snapshot)` | solo lectura (pin desde modo HUD) |
| Remoto (teléfono) | JSON UI del protocolo FD-294 (`screen_data{id, snapshot}`) | el mismo snapshot | `remote_action{op, args}` → `perform_action` |

El Control Remoto vive siempre en "modo HUD" con pantalla activa propia:
comparte el registro de `SuitOS` pero **no** su estado local. Sincronización
v1 = push completo del snapshot; binario/deltas solo si el perfil lo exige.
Los hápticos (`haptic{kind}`) son eventos de salida del núcleo, nunca de las
pantallas.

### Fases de implementación

- **F1 — esta delegación (Jules):** `SuitOS.gd` + `HUDableComponent.gd`
  (patrón `InteractableEntity`) + contratos de esta sección + tests
  `test_suit_os.gd` / `test_hudable.gd` con fuentes dummy. **No toca**
  RemoteControl*, Menu*, pausa ni cámara.
- **F2:** `ShipSystemBus` + pantalla "Sistemas de nave" (hereda FD-295) +
  estado de `MultiToolV2`.
- **F3:** modo HUD local (transición 1ra persona + pausa + radial
  `RadialSelectorV2`).
- **F4:** `screen_data` + `remote_action` + `haptic{tremor}` en el protocolo
  FD-294.

### Considered Options

- **Option A: HUD diegético puro (solo terminales físicos)** — desechado:
  ya validado en FD-295 que los puzzles multi-paso necesitan estado visible.
- **Option B: Un solo HUD global no modular** — desechado: no escala a
  HoloTerminals ad hoc ni a sesiones remotas independientes.
- **Option C: OdiseaOS modular con HUDables (seleccionada)** — reusa
  `HelmetHUDV2`/`TerminalHUDBridge`/`RadialSelectorV2`/`UIScaleCompensator`,
  extiende `InteractableEntity` con el mismo patrón de `InteractionMarker`,
  y sirve igual a local y remoto.
- **Pausa en modo HUD local: sí** (consola del traje, mundo espera);
  **pausa en remoto: no** (el teléfono no puede pausar el juego que estás
  jugando en la PC).

### Fuera de alcance (backlog)

- Multisesión remota independiente (N teléfonos).
- 3+ slots de widgets.
- Espejo de mapas/cámaras 3D (F2 de FD-294) — `SuitOS` deja el hook
  `scene_directive` listo.
- Hápticos más allá de tremor.
- Widgets configurables por el jugador (posición/tamaño).

## Files to Modify

- `core_v2/autoloads/SuitOS.gd` (nuevo autoload: registro, scorer, slots, señales, haptic bus)
- `core_v2/components/HUDableComponent.gd` (nuevo: vista + widget + registro, patrón `InteractionMarker`)
- `core_v2/components/shared/InteractableEntity.gd` (integrar HUDable opcional)
- `core_v2/things/SystemStatusHUD.gd` + `.tscn` (pantalla Sistemas de nave; hereda de FD-295)
- `core_v2/things/MultiToolHUD.gd` + `.tscn` (pantalla Multi-tool)
- `core_v2/player/MultiToolV2.gd` (exponer modo/carga/heat por señal)
- `core_v2/ui/hud/` (nuevo: contenedor de slots, radial de pantallas)
- `core_v2/ui/radial/RadialSelectorV2.gd` (reuso/adaptación a pantallas)
- `core_v2/ui/UIScaleCompensator.gd` (reuso para escalado)
- `core_v2/props/controls/HoloTerminalV2.gd` (registrar pantalla HUDable si aplica)
- `core_v2/net/RemoteControlServer.gd` / `RemoteControlClient.gd` (directiva `screen`, evento `haptic`)
- `docs/features/FD-295_hud_sistemas_persistente.md` (marcar superseded → FD-296)

## Verification

1. **Transición**: entrar a modo HUD hace transición a 1ra persona, el mundo
   pausa, se abre el radial, y **no** se disparan inputs del mundo (regresión
   del bug "OK pesca Partida Nueva").
2. **Relevancia**: despressurizar una línea de criocoolant → el widget
   automático cambia a Sistemas de nave sin abrir nada.
3. **Slot fijado**: pin de una pantalla persiste entre escenas y al cargar
   partida (sync con save/replay determinista).
4. **HUDable**: una HoloTerminal del Módulo Criogenia registra su pantalla y
   aparece en el radial.
5. **Remoto**: el teléfono muestra modo HUD en vivo mientras el juego corre
   en la PC (sin pausa); el HUD local y el remoto tienen pantallas
   independientes.
6. **Escalado**: widgets legibles y 60 fps en desktop, WebGL y móvil (Control
   2D sobre viewport 3D, sin viewports extra).
7. **Hápticos**: al integrarse FD-288, un Tremor vibra el teléfono remoto
   emparejado.
