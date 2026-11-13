# FD-295: HUD persistente de sistemas — indicadores siempre visibles para puzzles

**Status:** Superseded by FD-296 (OdiseaOS)
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-10
**Completed:** 2026-09-11 (absorbida en FD-296)

> **Nota (2026-09-11):** esta FD fue absorbida por `FD-296_odisea_os.md`. El HUD
> persistente de sistemas pasa a ser la pantalla "Sistemas de nave" de OdiseaOS
> con su widget resumen; el patrón se generaliza a cualquier interactuable
> (HUDables). Se conserva el contenido original como historial.

## Problem

Los puzzles de sistemas (criocoolant, plasma, atmósfera, energía auxiliar) se
leen solo desde HoloTerminals puntuales: al cerrar el terminal, el jugador
pierde de vista el estado de los sistemas y no puede razonar sobre el puzzle
(qué línea presuricé, qué ventil quedó atascado, qué falta). Hace falta una
capa de **indicadores persistentes en el HUD** para entender los puzzles y
controlar sistemas/herramientas sin reabrir terminales.

## Solution

Extender el patrón existente `HelmetHUDV2` + `TerminalHUDBridge` (ya resuelven
acoplar una UI a la cámara con focus/mouse) en vez de inventar una capa nueva:

1. **SystemStatusHUD**: panel minimalista, anclado a la cámara (hud_screen_x/y
   en esquina superior), que muestra el estado de los 4 sistemas como filas:
   nombre + ícono + estado (OK / DEGRADADO / FALLO) + 1 dato clave (presión,
   flujo, carga). Se alimenta de un nuevo autoload liviano `ShipSystemBus`
   (o señales del maestro FD-255) — solo lectura, sin lógica de puzzle.
2. **ToolSlotHUD**: slot fijo de herramienta activa (Multi-tool: modo láser /
   gloo) con su estado (carga/heat), reutilizando el estado de `MultiToolV2`.
3. **Reglas de legibilidad**: cada indicador tiene tooltip "¿qué significa?"
   accesible desde el terminal asociado (no popup inmersivo); colores del
   canon holográfico existente; se oculta en cinemáticas y menús.
4. **No es un menú de control**: la interacción sigue en los HoloTerminals
   físicos. El HUD muestra/afecta solo lo que la Multi-tool ya puede
   apuntar (ej: resaltar el ventil activo cuando está equipada).

### Considered Options

- **Option A: Diegético puro (solo terminales físicos)** — Pros: inmersión.
  Cons: en puzzles multi-paso el jugador no retiene el estado; fricción
  medida en playtests de criocoolant.
- **Option B: HUD de cámara vía HelmetHUDV2 (seleccionada)** — Pros: reusa
  infraestructura probada (attach, focus, mouse), barato, consistente con el
  look holográfico; se apaga con un flag. Cons: riesgo de sobrecargar la
  pantalla → se mitiga con formato de 4 filas + 1 slot.
- **Option C: Widget de pantalla completa tipo dashboard** — Pros: mucha info.
  Cons: saca al jugador del mundo; peso de UI; anti-diegético.

## Files to Modify

- `core_v2/things/SystemStatusHUD.gd` + `.tscn` (nuevo, extiende HelmetHUDV2)
- `core_v2/systems/ShipSystemBus.gd` (nuevo autoload — estado agregado de FD-256/257/258/259)
- `core_v2/player/MultiToolV2.gd` (exponer estado de modo/carga para el slot)
- `core_v2/props/decor/HelmetHUD.tscn` (variante de preset si aplica)

## Verification

1. En Módulo Criogenia: al presurizar una línea en el terminal, el HUD
   refleja el cambio sin abrir nada más.
2. Los 4 sistemas muestran estado correcto tras cargar una partida (sync con
   save/replay determinista).
3. El HUD no roba foco del mouse ni interfiere con la OTS camera (FD-042).
4. En WebGL/móvil mantiene 60fps (el panel es Control 2D sobre viewport 3D,
   sin viewports extra).
5. Toggle de accesibilidad en Settings para ocultar el HUD de sistemas.
