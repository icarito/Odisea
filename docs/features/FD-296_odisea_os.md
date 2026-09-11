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
