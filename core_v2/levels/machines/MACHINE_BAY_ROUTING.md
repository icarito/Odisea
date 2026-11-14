# Bahía de Máquinas — Ruteo no lineal del laberinto procedural

Estado: implementado (2026-11-14). Relacionado: FD-320 (ruta crítica de estaciones),
FD-321 (cinemáticas de transición). Implementación: `MachineBayMazeRouting.gd` +
`MazeRoutingGate.tscn`, integrados en `MachineBay.tscn`.

## Problema

El corredor de estaciones de la Bahía es **lineal**: entrás por −Z y avanzás por las
estaciones 1→5 en orden. El laberinto procedural (`LabyrinthSection` MST entre E1 y E2,
más el campo WFC streamed al este) existía, pero era un **callejón lateral de una sola
entrada y sin salida**: no cambiaba el recorrido ni el orden de exploración.

## Restricción de geometría (por qué no hay pasos junto a cada estación)

El corredor central ocupa `x ∈ [−7, 7]`; el este del corredor solo se abre en el
**bolsillo lateral entre las estaciones 1 y 2** (`x ∈ [5, 17]`, `z ∈ [8, 26]`), donde
vive `LabyrinthSection` y desde donde el `MazeEntryBridge` cruza al campo streamed
(`region_origin = (22, 0, 26)`). Abrir "pasos" junto a las estaciones 3/4/5 exigiría
catwalks nuevos que **trivializarían los saltos** que son justamente la mecánica de esas
estaciones (catapulta, brazo centrífugo). Por eso el ruteo no lineal se teje **dentro
del bolsillo/el campo**, no atravesando los saltos.

## Diseño: compuertas de servicio dirigidas por el estado de las máquinas

`MachineBayMazeRouting` es un director determinista que instancia compuertas
(`MazeRoutingGate`) en los enlaces del laberinto y las abre/cierra según el avance de
las **máquinas** — el "director de beats" es el propio `MachineLevel` (palancas de
estación + Orden 0001 cerrada).

| Enlace | Posición | Requisito | Qué habilita |
|---|---|---|---|
| `maze_entry` | boca oeste del laberinto (8.5, 0, 12) | `always` | entrar al laberinto desde el piso de entrada |
| `maze_exit` | salida este (17.5, 0, 27) | `item_active:SeesawLever` | atajo laberinto → aproximación de **Estación 2** |
| `field_link` | borde oeste del campo streamed (≈23.5, 0, 30.5) | `item_active:PendulumLever` | enlace al **campo de servicio WFC** |

### Rutas

- **corridor** — el corredor de estaciones (ruta crítica FD-320), siempre disponible e
  **intacto**.
- **maze** — boca (siempre) + paso a Estación 2 (abre al completar E1). Un atajo lateral
  entre E1 y E2 que compite con el corredor.
- **service_field** — la anterior + enlace al campo streamed (abre al completar E2). El
  laberinto WFC deja de ser un callejón sin salida: se integra como un tercer tramo.

Como `maze_entry` está siempre abierta y las otras dos abren con el progreso, a partir de
completar E1 hay **más de un camino simultáneo**, y cuáles existen cambia con el avance de
las máquinas → el orden de exploración deja de ser obvio.

### Por qué el nivel deja de ser predecible

1. Hay ≥2 rutas válidas en paralelo tras el primer beat de máquina, y no se anuncian.
2. El tramo streamed es **WFC procedural**: la topología exacta del campo no es fija ni
   memorizable; solo lo es su semilla (`seed_base`) y sus costuras deterministas.
3. La disponibilidad de cada enlace depende del estado de las estaciones, así que el
   conjunto de caminos evoluciona durante la partida.

## Determinismo (contrato §5.3 / replay)

- El estado de cada compuerta es una **función pura** del estado de `MachineLevel`
  (`get_item(name).is_active`, `is_work_order_completed()`): mismo replay → mismas
  compuertas. El director no guarda estado propio ni usa RNG.
- Las compuertas derivan de `InteractableBaseV2` (grupo `replay_sync`, snapshot de
  `is_active`/`anim_progress`); animación por `anim_progress`, sin `randf` ni reloj de
  pared.
- El streamer no usa RNG en runtime; la celda de enlace se fuerza con
  `set_junction_cells` (borde oeste + espejo en el chunk vecino) para que la compuerta
  siempre abra sobre piso walkable a altura 0.

## Reuso (no hay segundo streamer ni segundo sistema de compuertas)

- `LabyrinthSection` (MST) y `MachineBayLabyrinthStreamer` (WFC) tal cual; solo se les
  añadió la API opt-in `set_junction_cells`/`get_junction_world_position` al streamer.
- Compuertas derivadas de `InteractableBaseV2` (misma base que `LeverV2`,
  `SciFiDoorV2`, etc.).
- Estado de máquinas leído de `MachineLevel` (el mismo que usan los links del layout).

## Verificación

- `core_v2/tests/test_machine_bay_maze_routing.gd` — topología, apertura por progreso,
  >1 ruta abierta, pureza del estado, celda forzada del streamer y bloqueo físico del
  barrier (colisión on/off).
- `core_v2/tests/test_machine_bay_route.gd` — la ruta crítica FD-320 sigue completándose
  con el ruteo presente.
- `core_v2/tests/test_machine_bay_labyrinth_streamer.gd` — costuras deterministas
  intactas (la API de enlaces es opt-in; sin configurar, la generación es idéntica).

## Límites y seguimiento

- No se abren pasos físicos junto a las estaciones 3/4/5 (romperían su mecánica de salto);
  el ruteo enriquece el bolsillo/el campo. Si el diseño pide atajos entre estaciones
  lejanas, requiere un pase de geometría dedicado y revisión de las estaciones.
- El `BayShell` de respaldo (sin `build/machine_bay/bay_shell.glb`) es visual y sin
  colisión; el `MazeEntryBridge` cruza ahí como ya lo hacía antes de este cambio.
