# FD-048: Protocol Text Overlay (HUD)

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29

## Problem

El PRC-07 necesita mostrar el paso actual del protocolo en pantalla sin pausar
el juego. Overlay sutil en la HUD con estilo ambar monospace.

## Solution

Overlay de texto centro-superior que muestra paso actual y avanza
automaticamente. Se oculta tras 8s sin cambios. Se reabre con tecla P.

### Formato

PRC-07 | PASO 2/6: IDENTIFICAR MODULO

### Pasos

1. VERIFICAR SIGNOS VITALES (despertar)
2. IDENTIFICAR MODULO (salir capsula)
3. REPORTAR ESTADO A IA ODISEA (intercom)
4. INSPECCIONAR CONSOLA DEL MODULO (post-reporte)
5. RESTABLECER ENERGIA AUXILIAR (leer OD-02)
6. PROCEDER A ESCLUSA A-7 (energia activada)

### Transiciones

- Entrada: fade in 0.3s + slide down 10px
- Cambio paso: fade out 0.2s -> fade in 0.3s
- Auto-hide: 8s sin cambios -> fade out 1s
- Reabrir: tecla P -> fade in 0.3s -> oculta 4s

## Files to Create

- core_v2/ui/hud/ProtocolOverlay.gd
- core_v2/ui/hud/ProtocolOverlay.tscn

## Files to Modify

- core_v2/bootstrap/Boot.tscn — agregar ProtocolOverlay como Control

## Verification

1. Paso avanza al completar cada accion.
2. Overlay desaparece tras 8s sin cambios.
3. Tecla P lo reabre.
4. No bloquea input del jugador.
5. Font ambar monospace.
