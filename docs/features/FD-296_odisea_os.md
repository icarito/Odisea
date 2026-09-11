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

1. **Entrada: TAB** (acción `hud_mode`, añadida al input map del proyecto).
   Solo si la escena permite pausar y no hay menú abierto.
2. **El mundo pausa vía `PauseManager`** (`pause_hud_mode()`/`resume_hud_mode()`,
   métodos aditivos: `get_tree().paused` + audio `set_music_paused_by_menu`,
   **sin** instanciar `PauseMenu`). Decisión tomada con Sebastián: el modo HUD
   local es la consola del traje, el mundo espera — input limpio,
   determinismo intacto. La transición animada a primera persona de
   `HelmetHUDV2` (~0.45 s) queda como pulido posterior, no bloquea esta
   rebanada.
3. **Overlay full-screen** en `OverlayUIManager.ensure_overlay("HudModeOverlay",
   ..., SLOT_MODAL)` (sin CanvasLayer nuevo):
   a. **Selector radial** de pantallas (reuso `RadialSelectorV2`, mismo patrón
      de `ElevatorFloorSelector`: el gesto apunta, click/`ui_accept` confirma,
      `ui_cancel` sale; no roba cursor ni corta cámara, lee del stream de
      input para replay determinista). Slot A = automática, Slot B = fijada;
      confirmar sobre una pantalla la fija como pin. Con una sola pantalla se
      selecciona sola.
   b. **Vista de la pantalla seleccionada**: instancia `view_scene()` del
      HUDable. Para `HoloTerminalHUDable`, `view_scene()` reutiliza la UI
      interna del terminal (`CryoDiagnosticsUI.tscn`, la que ya renderiza el
      Viewport del HangingDisplay) — sin duplicar lógica ni usar
      ViewportTexture del mundo. Si `view_scene()` es null → fallback al
      widget ampliado. Sin pantallas registradas → placeholder "SIN PANTALLAS".
4. Al salir (segunda TAB, ESC o `ui_cancel`): `remove_overlay` + reanuda + HUD
   vuelve a modo widget. El menú de pausa normal (ESC) sigue en `PauseManager`
   intacto.

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
- **Persistencia al HUD (RESUELTA — opción b):** `SuitOS` ya pertenece al grupo
  `replay_sync` y expone `get_snapshot()`/`restore_snapshot()`. `CheckpointManager.capture_replay_sync_state()`
  recoge ese snapshot y `TeleportSystem` lo guarda dentro de
  `CheckpointResource.slots["last"]` (mismo camino que el resto del estado determinista).
  El pin y el último snapshot de cada slot viajan con el checkpoint existente: **no**
  hace falta API nueva en `PersistenceManager`. Al restaurar, SuitOS re-resuelve por
  `screen_id`; si la fuente no existe en la escena actual, el slot muestra el último
  snapshot con `"source": "offline"` (nunca desaparece en silencio).
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

### Integración con sistemas existentes (quién manda qué)

**Regla:** OdiseaOS aporta el **registro y los datos**; NO crea un segundo
sistema de presentación, pausa ni transporte. Cada responsabilidad que ya
tiene dueño se delega.

| Sistema existente | Qué aporta | Rol en OdiseaOS |
|---|---|---|
| `OverlayUIManager` (slots `Passive`/`HUD`/`Modal`, layer 115, `PROCESS`) | Contenedor de overlays con re-instanciación y manejo de `queue_free` ya resueltos | **Presentador de slots.** Los widgets de Slot A/B se montan acá (slot `HUD`). SuitOS no crea CanvasLayer propio. |
| `TerminalHUDBridge` + `HelmetHUDV2` | Attach a cámara activa, transición 0.45 s, radio de interacción, auto-close, bridge de input | **Presentador del modo HUD.** `view_scene()` se acopla por este bridge. `HelmetHUDV2` deja de ser un sistema aparte: pasa a ser *una pantalla más* del registro. |
| `PauseManager` | Dueño de la pausa Y del back de Android (`WM_GO_BACK_REQUEST`, `quit_on_go_back(false)`) | **Dueño de la pausa.** F3 le pide pausa a `PauseManager`; SuitOS **nunca** hace `get_tree().paused = true` por su cuenta. |
| `DebugConsoleManager` | Autoload que spawnea HUD, `pause_mode = PROCESS`, cierra en `pre_scene_swap`, y usa acción de input **propia** (documenta el bug del "input doble" por compartir `toggle_debug_menu`) | **Plantilla a copiar.** SuitOS replica el corte por escena y NO reclama la acción del debug console. Cada pantalla declara su propia acción de input. |
| `PlayerHintManager` | Overlay persistente con expiración, dedupe y refresh montado en `OverlayUIManager` slot `HUD` | **Patrón del widget persistente** (Slot B). |
| `CargolHUD` (`add_to_group("hud")`) | HUD ad-hoc del estado del dron | **Renovar en F2:** Cargol es una pantalla registrable; el grupo `"hud"` se retira. |
| `RemoteControlServer.send_ui_directive(op, payload)` (canal `ui` del protocolo) | Canal de directivas ya existente en FD-294 | **Transporte remoto.** F4 mapea `screen_data` a `send_ui_directive`, no a un canal nuevo. |
| `RuntimeControlManager` (autoload) | Host activo sólo en escenas de gameplay (`_is_gameplay_scene`) | Confirma que el layout local vs. remoto ya viene decidido por escena; SuitOS no reimplementa esa detección. |
| `EventBus` | ❌ **No existe como autoload** (`/root/EventBus` se consulta en `SignagePanel`/`AreaInfoScreen` pero no está en `project.godot`) | Aclaración: las señales de `SuitOS` **son** el bus de OdiseaOS. Si el proyecto adopta un `EventBus` global, SuitOS se suscribe — no lo crea. |

**Nada se supersede en F1–F2.** El riesgo real de FD-296 no es dejar atrás
sistemas, es **crear un segundo sistema paralelo** de HUD, pausa y transporte.
Los contratos de datos (snapshots, `allowed_actions`, `perform_action`) son
propios de SuitOS; la presentación y la pausa se delegan a los sistemas de
arriba.

### HoloTerminals como pantallas montables (F1.5)

Un `HoloTerminalV2` (y su heredero `WallTerminal`, p. ej. el `HangingDisplay`
de `Dome_Intro`) expone **la misma pantalla en tres formas**:

1. **Inmersiva (ya existe):** el jugador se acerca → `TerminalHUDBridge`
desprende `ScreenContainer/ScreenMesh` y lo monta frente a la cámara (ease
0.45 s, `hud_screen_*`). Sin cambios.
2. **Widget en slot (nuevo):** SuitOS dibuja el widget compacto con el mismo
snapshot, sin cámara ni attach. Es para ver el estado *sin* dejar de caminar.
3. **Modo HUD full-screen (F3):** TAB abre el overlay en `SLOT_MODAL`; la
   vista reusa la UI interna del terminal (p. ej. `CryoDiagnosticsUI`).

**Cómo se implementa (sin tocar las 1357 líneas de `HoloTerminalV2`):**

- Nuevo `core_v2/components/HoloTerminalHUDable.gd`, que **extiende
  `HUDableComponent`** y recibe por `export(NodePath)` el terminal fuente. Mismo
  patrón que `InteractableEntity` + `InteractionMarker`: componente aparte que
  se cuelga del terminal.
- `screen_id()` deriva de una ruta **estable y única** (p. ej.
  `"holoterminal:<owner.scene_file_path>"` o un `export(String) screen_id`
  explícito). **No** usar índices de árbol ni posiciones: rompería la
  persistencia entre saves.
- `widget_snapshot()` lee el estado que el terminal **ya publica** (el
  `HangingDisplay` ya tiene `CoolantSystemStatusUI` con señales de nivel por
  tanque). Solo lectura; nada de nodos ni NodePaths en el dict.
- `view_scene()` devuelve `null` y se marca `view_is_source` (la vista es el
  propio terminal, no una escena aparte).
- La **forma inmersiva queda intacta**: el componente es aditivo, no migra
  `HoloTerminalV2` en esta fase.

### Fases de implementación

- **F1 — HECHA (Jules, PR #334 ↔ `feature/FD-296-suitos-core`):**
  `SuitOS.gd` + `HUDableComponent.gd` (patrón `InteractableEntity`) +
  contratos + tests `test_suit_os.gd` / `test_hudable.gd`, con corte por
  `SceneManager.pre_scene_swap` (patrón `DebugConsoleManager`). Verificado
  localmente: 15/15 tests verdes.
- **F1.5 — HECHA (Jules, PR #335 ↔ `feature/FD-296-f1.5-visible-slice`):**
  primera **rebanada visible**. Objetivo: poder *ver* un widget cambiar por
  relevancia sin F3 ni F4.
  1. `HoloTerminalHUDable.gd` (wrapper de la sección anterior).
  2. `SuitOSWidgetHost.gd` + escena: escucha `widget_changed(slot, snapshot)`
     y monta `widget_scene()` en `OverlayUIManager.ensure_overlay(..., SLOT_HUD)`;
     reemplaza el nodo del slot al cambiar el snapshot (sin recrear el slot B
     si el `screen_id` no cambió). Si `widget_scene()` es `null`, cae a un
     render de texto del snapshot (útil para probar sin arte).
  3. `SuitOSContextDriver.gd`: alimenta `set_context({...})` desde
     `get_tree().get_nodes_in_group("player")` — distancia del jugador a cada
     fuente y `focus_id` si hay. Palanca: la fuente más cercana sube su
     relevancia; alejarse la baja. **Solo lectura del mundo.**
  4. `HangingDisplay` de `Dome_Intro.tscn` registrado como primera pantalla
     real (componente colgado del terminal existente).
  5. Test de integración: registrar → cambiar contexto simulado → el snapshot
     de Slot A cambia; pin → Slot B persiste. **No toca** RemoteControl*,
     Menu*, PauseManager, pausa, cámara ni `HoloTerminalV2`.
- **F2 — DELEGADA (Jules, sesión `7684582746836048852` ↔
  `feature/FD-296-f2-ship-systems`):** `ShipSystemBus` + pantalla "Sistemas de
  nave" (hereda FD-295) + estado de `MultiToolV2` + migrar `CargolHUD` a
  pantalla registrable.
- **F3 — en diseño (pendiente delegar):** modo HUD local. Entrada por acción
  `hud_mode` (TAB, añadida al input map); pausa vía `PauseManager` (métodos
  aditivos, **sin** instanciar `PauseMenu`); overlay full-screen en
  `OverlayUIManager.ensure_overlay(..., SLOT_MODAL)`; selector **radial** de
  pantallas (reuso `RadialSelectorV2` con el patrón de `ElevatorFloorSelector`:
  gesto apunta, confirmar fija pin en Slot B, `ui_cancel`/ESC/TAB sale); vista
  = `view_scene()` del HUDable (para `HoloTerminalHUDable` reusa la UI
  interna del terminal; si null → fallback al widget ampliado; sin pantallas
  → placeholder "SIN PANTALLAS"); slot A/B reales en pantalla.
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

- `core_v2/autoloads/SuitOS.gd` (nuevo autoload: registro, scorer, slots, señales, haptic bus, corte por `pre_scene_swap`)
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

0. **Corte por escena**: cambiar de escena con una pantalla activa no deja
   HUDs huérfanos (mismo patrón que `DebugConsoleManager`).
1. **Transición**: TAB entra/sale del modo HUD; el mundo pausa sin instanciar
   `PauseMenu`, se abre el overlay en SLOT_MODAL, y **no** se disparan inputs
   del mundo (regresión del bug "OK pesca Partida Nueva"). ESC abre el menú
   de pausa normal como siempre.
2. **Relevancia**: despressurizar una línea de criocoolant → el widget
   automático cambia a Sistemas de nave sin abrir nada.
3. **Slot fijado**: pin de una pantalla persiste entre escenas y al cargar
   partida (sync con save/replay determinista).
4. **HUDable**: una HoloTerminal del Módulo Criogenia registra su pantalla y
   aparece en el selector del modo HUD (TAB).
5. **Remoto**: el teléfono muestra modo HUD en vivo mientras el juego corre
   en la PC (sin pausa); el HUD local y el remoto tienen pantallas
   independientes.
6. **Escalado**: widgets legibles y 60 fps en desktop, WebGL y móvil (Control
   2D sobre viewport 3D, sin viewports extra).
7. **Hápticos**: al integrarse FD-288, un Tremor vibra el teléfono remoto
   emparejado.
