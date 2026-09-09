# FD-292: Consentimiento de telemetría first-run (todas las builds)

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-09-09
**Completed:** -

## Problem

El botón "Rechazar (sin telemetría)" del banner de la landing solo aplica a la
propia landing. El juego no respeta ninguna elección previa:

- **Builds descargables**: arrancan con `telemetry_enabled = true` por defecto
  (`core_v2/autoloads/SettingsManager.gd:22`) sin preguntar nunca. La única
  forma de apagarlo es Opciones → Telemetría, que nadie descubre sin aviso.
- **Versión web**: el shell (`core_v2/telemetry/html/odisea_shell.html`) envía
  sus propias métricas a `/api/telemetry` (`loader_start`, `player_released`,
  errores de carga) sin consultar consentimiento, y la landing no puede
  compartir su elección porque `odisea-game.netlify.app` es otro origen
  (localStorage no es compartido entre dominios).

Resultado: un usuario que rechaza telemetría sigue siendo telemetrizado en la
build descargable — y en la propia sesión web (métricas del shell).

Fuera de alcance: los chequeos de versión/actualizaciones (UpdateManager) no
son telemetría y quedan como están.

## Solution

Flujo de consentimiento first-run dentro del juego, común a todas las builds:

1. **Diálogo de privacidad first-run** (escena nueva
   `core_v2/ui/PrivacyConsentDialog`): se muestra una sola vez al boot, antes
   del menú principal, cuando `user://settings.cfg` no existe (proxy de
   primera ejecución; en web `user://` persiste vía IndexedDB entre
   sesiones).
   - Botones: "Aceptar" (telemetría + reportes de error ON) y "Rechazar"
     (ambos OFF).
   - Escribe `privacy/telemetry_enabled` y `privacy/error_reports_enabled` en
     SettingsManager y persiste de inmediato (`save_settings()`).
   - Enlaza a `/privacidad` del landing (política completa).
2. **Default OFF en first-run**: cuando `SettingsManager.load_settings()`
   falla a cargar (no hay config), `telemetry_enabled` y
   `error_reports_enabled` arrancan en `false` con `consent_asked = false`.
   El diálogo los enciende al aceptar. ANNAV2 ya soporta encendido en runtime
   vía `set_telemetry_enabled()` (la thread de red solo arranca si está
   habilitado; `_process` early-return con `_telemetry_enabled == false`).
3. **Shell web con gate propio**: el shell consulta
   `localStorage["odisea_telemetry_consent"]` (misma clave que ya usa el
   banner de la landing, pero en el origen del juego) antes del primer
   `sendMetric`. Sin decisión, buforea los payloads y los envía o descarta
   cuando el juego notifica vía `window.OdiseaShell.setTelemetryConsent(bool)`
   (llamado con `JavaScript.eval` desde el diálogo). Sin motor cargado y sin
   decisión → no se envía nada.
4. **Opciones** mantiene el toggle existente para cambiar de opinión después
   (ya funcional; `apply_privacy_settings()` propaga a ANNAV2).

### Considered Options

- **Option A**: Banner web-only + postMessage para pasar el consentimiento al
  juego embebido — descartado: el juego web se abre en ventana nueva
  (`window.open`), no en iframe; orígenes distintos; no cubre builds
  descargables ni TestFlight.
- **Option B**: Diálogo in-game first-run común (seleccionada) — una sola
  implementación cubre web + desktop + Android + TestFlight; el default OFF
  garantiza que sin decisión explícita no sale ningún dato.
- **Option C**: Solo texto legal / link a la política — no cambia el
  comportamiento; no cumple la expectativa creada por el botón "Rechazar".

## Files to Modify

- `core_v2/autoloads/SettingsManager.gd` (default OFF en first-run, flag `consent_asked`)
- `core_v2/ui/PrivacyConsentDialog.gd` + `.tscn` (nuevos)
- Escena de boot / menú principal (instanciar el diálogo)
- `core_v2/telemetry/html/odisea_shell.html` (buffer + gate de `sendMetric`, nuevo `OdiseaShell.setTelemetryConsent`)

## Verification

1. Perfil fresco (borrar `user://settings.cfg` / perfil del navegador) →
   arrancar build desktop → aparece el diálogo; elegir "Rechazar" → el
   central no recibe ningún heartbeat de esa sesión.
2. Mismo flujo eligiendo "Aceptar" → heartbeats normales desde el inicio.
3. Web, perfil fresco: `loader_start` NO sale hasta decidir; tras "Aceptar"
   los payloads buforeados se envían; tras "Rechazar" se descartan.
4. Relanzar: el diálogo no reaparece; el toggle de Opciones sigue funcionando
   y persiste.
