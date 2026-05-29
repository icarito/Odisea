# FD-046: OdiseaOS Status App

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29
**Depends on:** RetroWindow, DebugOverlay

## Problem

El jugador necesita ver el estado del modulo (presion, oxigeno, energia) sin
abrir una terminal cada vez. Una app de OdiseaOS que muestra datos en tiempo
real con estilo ambar/verde monospace.

## Solution

App OdiseaOS que sigue el patron existente:
- Extiende VBoxContainer, class_name OysStatus
- Usa RetroOS.tres como theme
- Se monta dentro de RetroWindow via DebugOverlay._mount_app()
- Muestra metricas del modulo en formato dashboard

### Layout

```
╝═══════════════════════════════════════════════
       ODISEA OS v2.1.4
       MODULO: CRIOGENIA
───────────────────────────────────────────────
OD-02  [ROJO] 0.82 atm
ENERGIA [VERDE] CONECTADA
PUERTA A-7 [VERDE] OPERATIVA
PUENTE B-4 [VERDE] EXTENDIDO
VENTILACION [VERDE] NORMAL
TEMP 12.4C [VERDE]
───────────────────────────────────────────────
>> ULTIMO REPORTE: TODOS LOS SISTEMAS OPERATIVOS
╝═══════════════════════════════════════════════
```

### Comportamiento

- Se abre desde la taskbar de OdiseaOS como ventana "System Status"
- Los valores se actualizan via senales desde los sistemas del modulo
- Color rojo (font_color) si fuera de parametros, verde si normal
- Sigue el patron de OysCalc.gd (VBoxContainer + labels + theme)

### Referencia de implementacion

Ver OysCalc.gd en core_v2/ui/retro/ para el patron exacto:
- Extiende VBoxContainer
- class_name OysStatus
- theme = preload("res://core_v2/ui/retro/RetroOS.tres")
- Labels con font_color override
- Se instancia con load("res://...").new() dentro de RetroWindow

## Files to Create

- core_v2/ui/retro/OysStatus.gd
- core_v2/ui/retro/OysStatus.tscn (opcional, puede ser solo codigo)

## Files to Modify

- core_v2/ui/retro/DebugOverlay.gd — registrar OysStatus como app
- Agregar boton en taskbar para abrir Status

## Verification

1. Abrir OdiseaOS -> taskbar -> Status -> ventana con metricas.
2. Antes de energia: OD-02 rojo, ENERGIA rojo.
3. Despues de Lever: ENERGIA verde, PUENTE verde.
4. Font verde/ambar monospace, fondo oscuro.
