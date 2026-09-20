# FD-311: Faltantes de la GUI de OdiseaOS — inventario priorizado

**Status:** Design
**Priority:** P1
**Effort:** -
**Created:** 2026-09-20
**Completed:** -
**Parent:** FD-296 (OdiseaOS)
**Relacionadas:** FD-310 (mapa de la GUI) · FD-304 · FD-305 · FD-306 · FD-307 · FD-308 · FD-309

## Propósito

Inventario **de una sola página** de todo lo que la GUI de OdiseaOS **no tiene todavía**,
clasificado por urgencia. Es el complemento de FD-310: FD-310 dice "qué existe y cómo
funciona"; FD-311 dice "qué falta y cuándo importa".

Regla: si un faltante ya tiene FD dueño, se referencia ese FD (no se duplica el spec).
Solo se listan como nuevos los huecos **sin dueño**.

**Escala de urgencia:**
- **P0 — bloquea el Vertical Slice del Acto I.** Sin esto no se puede jugar el Acto I de punta a punta.
- **P1 — afecta la jugabilidad del Acto I.** Se puede jugar, pero se nota roto o incómodo.
- **P2 — pulido / deuda que todavía no duele.** Vale registrarlo, no vale hacerlo aún.
- **Backlog — fuera del Acto I.** No hacer.

---

## P0 — bloquea el Vertical Slice

| # | Faltante | Estado hoy | Evidencia | Próximo paso |
|---|---|---|---|---|
| P0-1 | **Pantallas del Acto I sin proveedor hudable real.** Solo existen 4 pantallas (`player:flashlight`, `player:multitool`, `drone:cargol`, `ship:systems`) y el resto del contenido de `Dome_Intro` es inerte. | 4/≈15 pantallas | `core_v2/things/*Screen.gd`; FD-309 (placeholders), FD-307 (criocápsulas) | Cerrar FD-307 y FD-309 (ya tienen dueño) |
| P0-2 | **Modo HUD local (F3 de FD-296): "en diseño, pendiente delegar".** El overlay existe y funciona, pero el estado F3 sigue marcado como no entregado. | F3 no cerrada | FD-296 §fases; FD-310 §2.2 | Verificar con Sebastian si F3 se considera entregada por el merge de F1/F1.5 → cerrar la casilla o re-delegar |
| P0-3 | **Ninguna pantalla instancia su `HUDableComponent` desde `.tscn`.** Todo el wiring vive en código / `_enter_tree`. | 0 `.tscn` con `HUDableComponent` | recon: "No hay ningún `.tscn` que instancie `HUDableComponent`" | Es una decisión de patrón: dejar en código (documentar) o migrar a escenas. Ver FD-310 §5 |
| P0-4 | **El radial solo aparece con ≥2 pantallas.** Con el contenido actual de `Dome_Intro` puede no aparecer nunca, y el jugador no descubre el sistema. | `_open_radial` con ≤1 no abre | `HudModeOverlay._open_radial` | Depende de P0-1: más pantallas → radial útil |

## P1 — afecta la jugabilidad del Acto I

| # | Faltante | Estado hoy | Evidencia | Dueño |
|---|---|---|---|---|
| P1-1 | **Drawer de apps y favoritos** (inventario completo + "..." central). | No implementado | FD-305 | FD-305 |
| P1-2 | **Fixes estructurales del radial** (hub, orden por relevancia, tope 6, frescura de lista). | Parcial (hub y orden pendientes) | FD-306 | FD-306 |
| P1-3 | **Iconos de pantallas.** `hud_screen_icon` existe y está **muerto**: no se usa en una línea del juego; el layout de iconos está diferido a "fase 2". | Diferido | FD-306 §3 | FD-306 §3/fase 2 |
| P1-4 | **Interfaz diégetica con gamepad** (Y sticky, acorde rápido, drag con stick, criocápsulas). | Diseño | FD-304 | FD-304 |
| P1-5 | **4 slots en el control remoto.** Hoy el teléfono usa A/B; §6/F4 y §"Fuera de alcance" de FD-296 se contradicen (drift #2 de FD-310). | A/B en el teléfono | FD-296 §6/F4 vs §Out of scope | Decidir (ver Open Question, drift #2) |
| P1-6 | **Los 5 widgets son ~4 archivos casi idénticos sin base común** (`update_snapshot`/`set_snapshot` + PanelContainer). Cada widget nuevo reescribe lo mismo. | Sin base `HudWidget` | recon E §5-5; review de refactor §5 | Review de refactor (Fase 1) |
| P1-7 | **`OysCameras` no tiene salida por teclado** ("ESC handling removed") y `OysTransit` es huérfana total. | Deuda de accesibilidad/limpieza | recon B2 §5 | Limpieza barata (ver P2-3) |

## P2 — pulido / deuda

| # | Faltante | Estado | Evidencia |
|---|---|---|---|
| P2-1 | Búsqueda de texto en el drawer (diferida explícitamente a "cuando la lista larga lo justifique"). | Diferida 2026-09-19 | FD-305 §3.4 |
| P2-2 | Reordenar el radial a mano, categorías/tags de apps, subir el tope de 6 favoritos, paginación/carrusel. | Backlog explícito | FD-305 §Out of scope; FD-306 §Out of scope |
| P2-3 | **Código muerto verificable:** comandos `_cmd_calc`/`_cmd_nodescan` de `OYS_Console` llaman a métodos inexistentes (`_open_calc`/`_open_nodescan`) → siempre `{"ok":false}`; `OysStatus.update_status()` sin llamadores (datos fake permanentes); `TouchButton.gd` huérfano; `quit_requested` sin listener útil en el desktop. | Muerto | recon B2 §5; recon C §5 |
| P2-4 | **Priorización/relevancia sin feedback al jugador:** `relevance()` ordena el radial, pero nada comunica *por qué* una pantalla subió. | No existe | FD-310 §2.2 |
| P2-5 | Widgets configurables por el jugador (posición/tamaño). | Backlog explícito | FD-296 §Fuera de alcance |
| P2-6 | Hápticos más allá de tremor; sonido de linterna; parpadeo por batería baja. | Backlog | FD-296 / FD-298 §Out of scope |

## Backlog (fuera del Acto I)

- Multisesión remota independiente (N teléfonos) — FD-296 §Fuera de alcance.
- Espejo 3D de mapas/cámaras (F2 de FD-294) — el hook `scene_directive` está listo.
- Cinemáticas de entrada con sonido/voz — FD-297 §Out of scope.
- Recarga de batería de linterna (estaciones/celdas) — FD-298 §Out of scope.
- `eject_pod` / `wake_pod` en criocápsulas (Acto II) — FD-304/FD-307 §Out of scope.
- `AutoStubResolver` para placeholders — FD-309 §5 (deuda aceptada).
- i18n coreano (`ko`) — bloqueado por glifos Hangul ausentes en las fuentes.

## Sin dueño (requieren decisión de producto)

| # | Faltante | Por qué importa |
|---|---|---|
| D-1 | **Destino de la capa retro OYS.** Es una UI paralela al HUD (holoterminales verde/ámbar + desktop de debug) que comparte solo la fuente. Nadie sabe si se retira, se queda como herramienta interna o se promueve a diegético. | 2.400+ líneas sin dueño de producto (drift #10 de FD-310) |
| D-2 | **Reconciliación de los 9 drifts entre FDs** (FD-310 §7). En especial el #1 (modelo de slots A/B vs. 4 manuales) y el #2 (4 slots en el teléfono). | Los FDs son la spec; mientras se contradigan, cualquier implementación es "correcta" e "incorrecta" a la vez |
| D-3 | **Catálogo central de ops.** `allowed_actions_list` es un `Array[String]` validado en runtime; no hay enum ni errores tipados (`{"ok":false,"error":String}`). | Cada pantalla publica su propio vocabulario; el remoto no puede validar nada por adelantado |
| D-4 | **Performance del HUD:** `reevaluate_slots()` reconstruye snapshots de los 4 slots en cada `set_context` (cada frame, 10 Hz vía `SuitOSContextDriver`), y `HudModeOverlay._widget_host()` recorre el grupo por nodo en cada frame de arrastre. | El guard por `hash()` evita señales, no el cómputo — medir en el objetivo low-end |
