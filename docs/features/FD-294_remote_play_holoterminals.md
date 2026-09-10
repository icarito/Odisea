# FD-294: Remote Play — HoloTerminals en el teléfono (pairing con la sesión de PC)

**Status:** Deferred
**Priority:** P2
**Effort:** Large
**Created:** 2026-09-10
**Completed:** -

## Problem

Sebastián quiere controlar sistemas de la nave desde el teléfono mientras juega
en PC, al estilo DroidPad. La idea original era integrarse con DroidPad, pero
es limitado (botones fijos, sin reuso del estilo visual del juego). Mejor
alternativa: **reutilizar las UIs de los HoloTerminals existentes** y
espejarlas en el teléfono, con un item de menú principal + proceso de pairing.

## Solution

Cliente ligero en el teléfono (web export o APK existente) que se conecta por
WebSocket a la sesión de juego en PC y renderiza el estado de un HoloTerminal
remoto. El PC es la fuente de verdad; el teléfono envía eventos de input.

### Alcance real (por qué es Large, no "solo un menú")

1. **Servidor WebSocket embebido en Godot 3** (WebSocketServer nativo existe,
   pero hay que montar protocolo propio, rooms y reconexión).
2. **Pairing**: LAN discovery o PIN/QR de 6 dígitos; estado de conexión
   visible en menú; manejo de desconexión a mitad de puzzle.
3. **Protocolo de UI remota**: serializar layout + estado de cada
   HoloTerminal (paneles, botones, sliders, indicadores) hacia el teléfono y
   eventos de vuelta (tap, drag, selección). Esto es el grueso del trabajo.
4. **Item de menú principal**: "Vincular dispositivo" con QR + estado.
5. **Auth mínima**: token efímero del pairing; nadie más en la LAN controla la nave.

### Considered Options

- **Option A: DroidPad / protocolos genéricos** — Pros: cero protocolo propio.
  Cons: UIs limitadas y ajenas al estilo del juego; no reusa HoloTerminals;
  mapeo manual por pantalla.
- **Option B: Espejo de HoloTerminals sobre WebSocket propio (seleccionada)** —
  Pros: reusa TerminalUI/HoloTerminalV2, look consistente, control total del
  protocolo; el build móvil ya existe (APK + TestFlight). Cons: protocolo y
  sync de estado a cargo nuestra; 1–2 semanas bien hecho.
- **Option C: Segunda instancia del juego en el teléfono en modo "panel"** —
  Pros: cero protocolo de UI. Cons: no hay sesión compartida; sync del mundo
  completo sería más caro que espejar UIs.

## Files to Modify

- `core_v2/net/RemotePlayServer.gd` (nuevo — WebSocketServer + pairing)
- `core_v2/net/RemotePlayProtocol.gd` (nuevo — serialización de estado HoloTerminal)
- `core_v2/ui/Menu.gd` (item "Vincular dispositivo" + QR/estado)
- `core_v2/things/HoloTerminalV2.gd` (hook de broadcast de estado cuando hay cliente)
- `core_v2/things/HoloTerminalViewportInput.gd` (inyección de input remoto)

## Dependencias

- FD-263 (touch universal): el input del teléfono reusa esa capa.
- FD-295 (HUD persistente): el panel de indicadores remoto debería existir
  primero in-game; el teléfono solo lo espeja.

## Verification

1. PC corre el juego; en menú se elige "Vincular dispositivo"; aparece QR/PIN.
2. El teléfono (mismo LAN) escanea/ingresa PIN y muestra "Conectado a <sesión>".
3. Un HoloTerminal de sistema abierto en PC se espeja en el teléfono; un tap
   en el teléfono togglea el sistema y se refleja in-game.
4. Corte de red a mitad de interacción: el teléfono muestra "Reconectando…"
   y al volver recupera el estado sin corromper el puzzle.
5. Sin conectar, cero overhead de red y gameplay idéntico al actual.
