# FD-047: Intercom App (OdiseaOS)

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29
**Depends on:** HoloTerminalV2, RetroWindow

## Problem

El paso 3 del PRC-07 requiere que Elias reporte su estado a la IA Odisea.
Necesitamos una app de OdiseaOS para el intercom, montada en un WallTerminal
como kiosk mode (fullscreen, sin taskbar).

## Solution

App OdiseaOS OysIntercom que sigue el patron existente (OysCalc.gd).
Se monta dentro de un WallTerminal en modo kiosk para que sea la unica app
visible en esa terminal.

### Patron de implementacion

- Extiende VBoxContainer, class_name OysIntercom
- Usa RetroOS.tres como theme
- En kiosk mode: se asigna directo al contenido del WallTerminal sin ventana
- Labels con font_color verde/ambar
- Un solo boton "Reportar Estado"

### Layout

```
╝═══════════════════════════════════════════════
       INTERCOM — CRIOPS CH.7
───────────────────────────────────────────────
[LOG]
> 12:01 UTC — CRIOPS: SINCRONIZACION COMPLETA
> 12:01 UTC — SUPERVISOR: REPORTE PENDIENTE
───────────────────────────────────────────────
[>> REPORTAR ESTADO]  <- boton
───────────────────────────────────────────────
>> ELIAS: "Reporte de rutina — T-3 CriOps."
>> ODISEA: "Estado registrado. Proceda."
╝═══════════════════════════════════════════════
```

### Comportamiento

1. WallTerminal en kiosk mode muestra la app OysIntercom.
2. Muestra log de comunicaciones previas.
3. Boton "Reportar Estado" ejecuta el reporte.
4. Al pulsar: animacion "transmitiendo..." + dialogo Elias/Odisea.
5. Despues del reporte, boton se deshabilita.
6. Opcional: audio de tono de llamada.

### Kiosk mode

Cuando HoloTerminalV2 tiene attach_to_active_camera = false y se usa como
WallTerminal fijo, la app debe ocupar todo el viewport sin ventanas.

### Referencia

Ver OysCalc.gd en core_v2/ui/retro/ para el patron exacto de app.

## Files to Create

- core_v2/ui/retro/OysIntercom.gd
- core_v2/ui/retro/OysIntercom.tscn (opcional)

## Files to Reuse

- core_v2/props/WallTerminal.tscn — base visual
- core_v2/things/HoloTerminalV2.gd — logica de terminal
- core_v2/ui/retro/RetroOS.tres — theme

## Verification

1. Elias se acerca a WallTerminal, ve app OysIntercom.
2. Pulsa boton "Reportar Estado" -> dialogo de Odisea.
3. Boton se deshabilita.
4. Font verde/ambar monospace.
