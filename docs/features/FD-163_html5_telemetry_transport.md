# FD-163: Transporte de telemetría ANNA V2 en HTML5 (WSS)

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-06-08
**Completed:** -

> Sub-feature de [FD-162 (Odisea Bridge)](FD-162-odisea-bridge.md). Define cómo un build
> **HTML5 (WebGL)** entrega telemetría ANNA V2 al peer/central, dado que el browser impone
> restricciones que no aplican a desktop/Android.

## Problem

ANNA V2 ([core_v2/anna/v2/ANNAV2_Thread.gd](../../core_v2/anna/v2/ANNAV2_Thread.gd)) ya
reporta telemetría a un peer local (`:4999`) y, en desktop/Android, cae al nodo central
(`:5003`) cuando no hay peer, autenticando con `ODISEA_BRIDGE_TOKEN`. **HTML5 no encaja en ese
modelo** y hoy ni siquiera intenta el central: la rama `web` de `_discover_peer` retorna
`ws://localhost:4999/ws` y nunca alcanza el fallback.

Restricciones del browser:

1. **Sin variables de entorno** — `OS.get_environment()` retorna `""` en web. Toda la config
   (`ODISEA_BRIDGE_TOKEN`, `ANNA_V2_CENTRAL`, `ANNA_V2_NO_CENTRAL`) es inalcanzable.
2. **Sin TCP crudo / sin `_check_port`** — `StreamPeerTCP` no existe en web; el port-scan de
   discovery no aplica.
3. **Sin mDNS** — los browsers bloquean UDP; no hay descubrimiento `_odisea._tcp`.
4. **Mixed content** — una página servida por `https://` **no puede** abrir `ws://`; el browser
   lo bloquea. Requiere `wss://` (WebSocket sobre TLS).

Bloqueante actual: **el central no tiene TLS** (`ws://35.182.238.36:5003`). Por lo tanto, un
build HTML5 servido por https **no puede** alcanzar el central hasta resolver esa infra.

## Solution

Definir una interfaz de configuración y transporte específica para web, equivalente a la de
env vars en nativo, pero por **parámetros de URL** (parseables con `JavaScript.eval`, patrón ya
usado en [ANNAV2.gd](../../core_v2/anna/v2/ANNAV2.gd) `_get_url_param`).

### Configuración por URL query params (reemplazo de env en web)

| Param | Equivalente nativo | Default |
|-------|--------------------|---------|
| `?bridge=host:port` | `ANNA_V2_BRIDGE` | — (si se da, fuerza ese peer) |
| `?central=host:port` | `ANNA_V2_CENTRAL` | `35.182.238.36:5003` |
| `?token=...` | `ODISEA_BRIDGE_TOKEN` | `odisea-dev-insecure` (dev) |
| `?nocentral=1` | `ANNA_V2_NO_CENTRAL` | off |
| `?scheme=ws\|wss` | (auto) | auto según el protocolo de la página |

Ejemplo: `https://juego.example/index.html?central=bridge.example:443&token=XXXX`

### Regla de esquema (ws vs wss)

- Auto: `wss://` si `window.location.protocol === "https:"`, si no `ws://`.
- `?scheme=` fuerza el esquema (útil para dev local sobre http apuntando a un wss, o viceversa).
- Detección vía `JavaScript.eval("window.location.protocol")`.

### Precedencia de discovery en web

A diferencia de nativo (env → mDNS/port-scan → central), en web:

1. `?bridge=host:port` → conectar a ese peer.
2. Si no, y `?nocentral` no está → `?central=` (o el default) con la regla de esquema.
3. Si `?nocentral=1` → solo intentar peer (no reportar al central).

Sin TCP scan ni mDNS: el browser solo puede abrir las URLs WS que se le indiquen.

### Handshake / heartbeat (sin cambios)

El protocolo es idéntico al de nativo. ANNA V2 ya envía `token` + `peer_id` en el handshake
([ANNAV2_Thread.gd](../../core_v2/anna/v2/ANNAV2_Thread.gd) `_send_handshake`); el central valida
el token y el peer local lo ignora. Los frames se mandan como **TEXT** (`WRITE_MODE_TEXT`), que
es lo que el peer y el central parsean.

### Dependencia de TLS (el bloqueante real)

HTML5 desde una página `https://` solo conecta cuando el central exponga **`wss://`**. Esto es
infra, no código de cliente. Caminos recomendados:

- **Caddy** como reverse proxy delante del `:5003` → HTTPS/WSS automático con Let's Encrypt
  (requiere un dominio apuntando al host del central).
- **Cloudflare Tunnel** delante del central → entrega `wss://` sin abrir puertos ni gestionar
  certificados.

Hasta tener TLS, HTML5→central solo funciona desde páginas **http/localhost** (dev); en https
queda peer-only.

### Comportamiento hasta tener TLS

En web, si el esquema resuelto es `wss` pero el central no responde, **no spamear errores**:
respetar `RECONNECT_INTERVAL_MS` (2s) y degradar en silencio a peer-only. La ausencia de
bridge nunca debe afectar el juego (igual que en nativo).

### Seguridad

- `?token=` queda **visible en la URL** y un build web es totalmente inspeccionable. El token
  fuerte de **lectura** (`/status`, `/sessions`, dashboard) **nunca** debe viajar al cliente.
- Para ingest desde web, usar el token débil/rotativo (ver discusión de tokens en
  [FD-162](FD-162-odisea-bridge.md)); la telemetría es write-only/inofensiva, lo sensible es
  leer la data agregada de todos los players.

## Considered Options

- **Option A**: Implementar ya la plomería web (params + fallback + auto-wss) — Pro: lista para
  activar; Con: queda **código muerto** en https hasta que exista TLS, y esconde el bloqueante
  real (la infra TLS).
- **Option B (Selected)**: Definir la interfaz ahora (este doc) e implementar cuando el central
  tenga `wss://`. Evita código muerto y deja explícito que el siguiente paso es infra, no
  cliente.

## Files to Modify (implementación futura)

- `core_v2/anna/v2/ANNAV2.gd` — extender el parseo de URL params (`bridge`, `central`, `token`,
  `nocentral`, `scheme`) reusando `_get_url_param`, y pasarlos al thread.
- `core_v2/anna/v2/ANNAV2_Thread.gd` — rama `web` de `_discover_peer`: aplicar precedencia y la
  regla de esquema; ya existen `_central_url` / `_bridge_token` / `_central_enabled`.
- Infra (fuera del repo): TLS en el central (Caddy o Cloudflare Tunnel).
- `.claude/skills/odisea-telemetry/SKILL.md` — agregar sección HTML5 al implementarse.

## Verification

1. Export HTML5 servido por **http local** + peer en `:4999` → `http://localhost:4999/status`
   muestra el player del build web.
2. Con central tras **`wss://`** (TLS) y página **https** → `/status` del central muestra el
   player web.
3. `?nocentral=1` → el build web no intenta el central (solo peer).
4. `?bridge=host:port` → fuerza ese peer ignorando el default.
5. `?scheme=ws` en página https → respeta el override (para casos de dev).
