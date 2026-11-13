# FD-225: Version Check — notificación de nueva versión via telemetría

**Status:** Open
**Priority:** Medium
**Effort:** Small
**Created:** 2026-06-16

## Problem

El juego no tiene forma de avisar al jugador cuando hay un build más nuevo disponible. En WebGL el jugador sigue jugando sobre una versión vieja hasta que alguien le avise. En native ni siquiera hay actualización automática.

## Solution

Un componente Autoload que consulta la versión actual via el bridge central al iniciar el juego (y periódicamente), la compara con la versión local, y muestra un aviso no obstructivo si hay una más nueva.

### Fuente de verdad

GitHub Releases del repo `icarito/Odisea`. El bridge central expone un endpoint que refleja el último release.

### Bridge endpoint (existente o nuevo)

```
GET /game/version
```

Respuesta:
```json
{
  "version": "v0.3.2",
  "latest_release_url": "https://github.com/icarito/Odisea/releases/tag/v0.3.2",
  "web_url": "https://odisea-game.netlify.app",
  "downloads_page": "https://icarito.github.io/odisea-neon-dreams/#downloads"
}
```

### Comportamiento por plataforma

| Plataforma | Mensaje |
|------------|---------|
| WebGL | "Nueva versión disponible — se obtendrá al recargar la página" |
| Native (Windows/Linux/Android) | "Nueva versión disponible" con enlace a la página de descargas |

### Componentes en el juego

**Nuevo Autoload:** `VersionChecker.gd`

- Al `_ready()`: hace HTTPRequest al bridge
- Si la respuesta es más reciente que `Constants.GAME_VERSION` (constante hardcodeada en el build), setea `has_update = true`
- Expone señal `new_version_available(version_data: Dictionary)`
- Opcional: re-consulta cada 30 min mientras el juego esté abierto (timer)

**Nuevo UI overlay (opcional):** `VersionNotification.tscn`

- Aparece como un toast minimal en la esquina, no modal
- En WebGL: texto "v{NUEVA} disponible — recarga para obtenerla"
- En Native: texto "v{NUEVA} disponible" + botón "Ver descargas" que abre URL
- Se puede descartar
- No reaparece hasta nuevo check

### Comportamiento offline

Si el bridge no responde (timeout o error), no se muestra nada. Silencio elegante — no bloquear al jugador.

## Files to Modify/Create

- `core_v2/system/VersionChecker.gd` (nuevo)
- `core_v2/Constants.gd` (agregar `const GAME_VERSION = "v0.3.2"`)
- `core_v2/ui/VersionNotification.tscn` (nuevo, overlay)
- `core_v2/ui/VersionNotification.gd` (nuevo)
- `project.godot` (registrar Autoload)

## Notas sobre el bridge

El bridge (`odisea_central.py`) ya corre en `odisea.educa.juegos:5003`. Necesita un nuevo endpoint `/game/version` que:

1. Consulta la API de GitHub para el último release de `icarito/Odisea`
2. Cachea la respuesta (TTL ~5 min)
3. Devuelve el JSON descrito arriba

Esto es código de bridge, no de juego — lo implementa quien mantiene el bridge.

## Verification

1. Build con `GAME_VERSION = "v0.3.1"` habiendo un release v0.3.2 real
2. Iniciar juego conectado a internet → debe aparecer el toast
3. Hacer clic en descartar → no reaparece en la misma sesión
4. Iniciar sin internet → no aparece nada, sin errores en consola
5. WebGL: texto dice "recargar". Native: texto dice "Ver descargas"
6. Subir GAME_VERSION a v0.3.2 → al recargar, no aparece el toast
