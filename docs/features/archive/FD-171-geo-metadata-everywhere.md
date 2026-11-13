# FD-171: Geo Metadata Everywhere

**Status:** Draft
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-06-13

## Problem

Los datos de geolocalización (country, city, coordinates) solo existen en la pestaña Mapa del dashboard. Esos datos vienen de `geo_tags.db`, poblado por `import_nginx_geo.py` desde logs de nginx (visitantes web).

Las vistas de History, Sesiones y Players muestran IDs anónimos sin país/ciudad. Los heartbeats del juego no tienen IP, así que no se pueden joinear con `geo_tags.db`.

## Technical Analysis

### Option A: IP hash en heartbeats (schema migration)

Agregar columna `ip_hash TEXT` a la tabla `heartbeats`. Capturar IP en `handle_ws`, hashearla, guardarla con cada heartbeat. Al consultar, hacer LEFT JOIN con `geo_tags.db`.

- ✅ Simple, cubre todos los heartbeats históricos
- ❌ IP hasheada permanente en DB de telemetría
- ❌ Cross-DB JOIN (ghosts.db ↔ geo_tags.db), requiere ATTACH o merge en Python
- ❌ Frágil si cambia el hash salt

### Option B: Tabla separada `player_geo`

Tabla nueva en `ghosts.db`: `player_geo(player_id TEXT PRIMARY KEY, country TEXT, country_code TEXT, city TEXT, first_seen REAL, last_seen REAL)`. Cuando llega un heartbeat, el servidor captura IP, la hashea, busca en geo_cache, y escribe en `player_geo`. Los endpoints de ghosts joinean con esta tabla (misma DB, JOIN nativo).

- ✅ Sin cross-DB JOINs — `player_geo` está en ghosts.db
- ✅ IP no se almacena, solo el resultado geo (country/city)
- ✅ JOIN nativo SQLite, performance óptima
- ✅ Si cambia el salt, solo se repuebla `player_geo`, no se tocan heartbeats
- ❌ Nueva tabla, pero ligera (~100-500 rows)

### Option C: En memoria + enriquecer on-the-fly

Capturar `peer_id → ip_hash` en memoria al conectar. Al servir ghosts/players, enriquecer con geo_cache en Python antes de devolver. Sin almacenamiento permanente.

- ✅ Cero migración de schema
- ❌ Solo funciona para sesiones activas (memoria se pierde en restart)
- ❌ No sirve para History (necesita datos persistentes)

## Recommendation: Option B

`player_geo` en ghosts.db. El servidor resuelve geo al vuelo cuando llega cada heartbeat y persiste en esta tabla. Los endpoints de lectura joinean con `player_geo` para devolver country/city.

## Backend Spec (odisea_central.py)

### 1. Captura de IP al conectar

En `handle_ws`, después del handshake exitoso:
```
raw_ip = request.remote
ip_hash = sha256(salt + ":" + raw_ip).hexdigest()[:16]
self.peer_ip[peer_id] = ip_hash  # dict en memoria
```

### 2. Tabla `player_geo`

```sql
CREATE TABLE IF NOT EXISTS player_geo (
    player_id TEXT PRIMARY KEY,
    country TEXT,
    country_code TEXT,
    city TEXT,
    first_seen REAL,
    last_seen REAL
);
```

### 3. Geo-tagging en `_process_heartbeat`

Cuando llega un heartbeat:
```
ip_hash = self.peer_ip.get(peer_id)
if ip_hash and ip_hash in geo_cache:
    UPSERT INTO player_geo (player_id, country, country_code, city, first_seen, last_seen)
```

### 4. Endpoints a modificar

| Endpoint | Cambio |
|----------|--------|
| `GET /ghosts` | LEFT JOIN player_geo, devolver country/city en cada row |
| `GET /ghosts/sessions` | LEFT JOIN player_geo, devolver country/city |
| `GET /ghosts/active` | Enriquecer desde `player_geo` en DB |
| `GET /api/geo-players` | Agregar game players (los que tienen entrada en player_geo) |

### 5. Response format

Cada row de ghost/player gana tres campos opcionales:
```json
{
  "player_id": "1780893709-177616192",
  "country": "Brazil",
  "country_code": "BR", 
  "city": "Brasiléia"
}
```

## Frontend Spec (dashboard)

### Componentes a modificar

1. **PlayerCard.tsx** — mostrar `🇧🇷 ciudad` debajo del player_id
2. **PlayerBottomSheet.tsx** — country + city en cada fila
3. **SessionHistory.tsx** — columna país en lista de sesiones
4. **GlobeView.tsx** — ya recibe `geoPlayers`, confirmar que muestra game players

### Data flow

Los componentes leen `country`, `country_code`, `city` de los datos que ya devuelven los endpoints. Sin fetch adicional. El enriquecimiento es 100% server-side.

### Flag emoji helper

```ts
function countryFlag(code: string): string {
  if (!code || code.length !== 2) return "";
  return String.fromCodePoint(...[...code.toUpperCase()].map(c => 0x1F1E6 + c.charCodeAt(0) - 65));
}
```

## Scope

**In scope:**
- Backend: `player_geo` table, IP capture, geo-tagging en heartbeat, JOIN en queries
- Frontend: country/city en PlayerCard, PlayerBottomSheet, SessionHistory, GlobeView

**Backlog:**
- Filtro por país en FiltersDrawer
- Columna país en HistoricalTable
- Mapa de calor por país en stats

## Files Changed

- `odisea_central.py` — IP capture, player_geo table, JOIN en queries
- `dashboard/src/components/PlayerCard.tsx`
- `dashboard/src/components/PlayerBottomSheet.tsx`
- `dashboard/src/components/SessionHistory.tsx`
