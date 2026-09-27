# Debug HUD (Odisea)

Port acotado de `addons/debug_hud/` de gdtk (colector de metricas + vista ImGui) a
Odisea. Fuente: `/run/media/icarito/DATA/icarito/Proyectos/gdtk` (`SPEC-hud.md`,
`SPEC-hud-remote.md`).

## Que cambia respecto a gdtk

- Sin transporte TCP propio (`remote_source`/`hud_snapshot`/tokens): Odisea ya tiene
  su propio control remoto (`core_v2/net/RemoteControlManager.gd`) y HUD de telefono
  (`core_v2/ui/hud/RemoteHudBackend.gd`). El resumen de metricas viaja por ese canal
  como una pantalla HUDable mas (`core_v2/things/DebugHudScreen.gd`,
  `system:performance`), no por un socket aparte.
- Sin pestana de consola / linea de comandos: Odisea ya tiene una consola de debug
  diegetica completa (`core_v2/ui/retro/OYS_Console.gd`, tecla backtick ->
  `DebugConsoleHUD`). Este HUD solo trae Graficas y Monitores.
- Tecla **F1** (no backtick): backtick ya es `toggle_debug_console` en el input map
  de Odisea.
- `debug_metrics.gd` usa `Engine.get_singleton("DebugLog")` en vez del identificador
  global `DebugLog` directo: el binario pinneado de Odisea (v0.5.3) no compila el
  modulo `imgui`, y ese identificador no existe ahi. `debug_metrics.gd` se precarga
  siempre (colector sin ImGui), asi que tiene que compilar en los dos binarios.

## Piezas

- `debug_metrics.gd` (`DebugMetrics`, `Reference`): colector, sin ImGui. Corre en
  cualquier binario.
- `debug_hud.gd` (autoload `DebugHud`): siempre crea el colector si esta habilitado;
  solo construye la vista ImGui (`debug_hud_view.gd`) si
  `ClassDB.class_exists("ImGuiCanvas")` y la politica `render_local` lo permite.
- `debug_hud_view.gd` (`extends ImGuiCanvas`, SIN `class_name`, SIN `preload`): se
  carga con `load()` diferido para no romper la compilacion en el binario pinneado
  (mismo patron que `core_v2/props/criopod/CryoPodUI.gd._build_imgui_screen`).

## Politica `enabled` / `render_local`

- `enabled`: `OS.is_debug_build()` o `ProjectSettings` `debug_hud/enabled_in_release`
  (opt-in explicito). En release sin ese setting, el HUD no existe: ni colector ni
  vista ni pantalla HUDable.
- `render_local` (solo la VISTA local; el colector sigue igual):
  `not (GLES3VendorGate.is_low_tier() and GLES3VendorGate.is_flat_mode())`, con
  override por env `ODISEA_DEBUG_HUD_LOCAL=0|1` (gana sobre el gate).

## Pantalla HUDable "Rendimiento"

`DebugHudScreen` (`system:performance`) se instancia como hijo del autoload
`DebugHud`, no de una escena de nivel: existe sin importar el mapa activo. Expone
`widget_snapshot()` con un RESUMEN (6 numeros + 2 series cortas de 20 muestras para
un sparkline), no el snapshot completo del colector (~100 KB con las 600 muestras de
cada serie). Viaja al telefono igual que cualquier otra pantalla, coalescido por
`SuitOSRemoteBridge` a 10 Hz maximo; `DebugHudScreen` solo pide reenviarlo a 2 Hz
(`notify_state_changed()` cada 0.5 s).
