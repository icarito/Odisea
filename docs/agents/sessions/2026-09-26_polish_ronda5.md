# Polish ronda 5 — 2026-09-26

Modo despachador (ver skill `iterative-list-hacking`, sección "Modo despachador"): el lead planea,
Sonnet/Kilo ejecutan, sin tests hasta que un tema se estabilice.

## Items

### T1 — Telemetría: menú/boot/pausa fuera de las stats de FPS
Heartbeats durante Boot.tscn, Menú y pausa entran a las stats de FPS del dashboard y las ensucian.
Queremos seguir sabiendo que están en menú/boot (p. ej. para load times) pero excluirlos de las
stats de rendimiento.

### T2 — Dashboard: coherencia de muertes, nuevas sesiones y cambios de nivel
Hoy el dashboard no distingue esos eventos. Requiere análisis del modelo de datos.

### T3 — Salud del nodo central (prod)
Revisión solo lectura.

### T3 — hallazgos (health check 2026-09-26)
1. CRÍTICO disco 89% (11G libres): `data/backups/` = 12G (8 copias de ghosts.db, sin rotación en
   `make deploy-central`, Makefile ~296); `heartbeats` 1.16M filas sin retención (solo incidentes
   tienen prune, `odisea_central.py:708-731`). **Pendiente decisión de Sebastián** (borrar backups
   en prod / política de retención).
2. ALTO ~3000 "database is locked"/2 días: `scripts/import_ghosts_to_sqlite.py` conectaba sin
   busy_timeout. **Arreglado local** (timeout=8 + WAL), falta deploy.
3. Memoria del proceso 3.9G (pico 5.6G de 7.8G), sin OOM. Vigilar.
4. OK: servicio estable 1 semana, prod == HEAD, endpoints 200, nginx limpio.

### T1+T2 — Contrato de telemetría v2 (fuente de verdad para K1/K2/K3)

Diagnóstico (mapa completo 2026-09-26): no hay eventos discretos, todo viaja en el heartbeat;
`paused` se genera pero el central no lo persiste; FPS se filtra solo por `focused`
(`odisea_central.py:119`), Boot/Menu/pausa entran a los promedios; la muerte no se telemetría
(`TeleportSystem.gd:362`); `transition` se persiste pero el dashboard no la usa;
`EventTimeline.tsx` tiene tipo `scene_change` que nadie emite. session_id = por proceso
(`ANNAV2.gd:84`) — se mantiene así.

**Campo nuevo `player.phase`** (string, cada heartbeat), calculado en `ANNAV2._update_telemetry`,
prioridad en este orden:
- `"loading"` — hay una transición de SceneManager en curso (stage distinto de completed/failed)
- `"boot"` — scene == "Boot"
- `"menu"` — scene == "Menu"
- `"paused"` — `get_tree().paused`
- `"play"` — resto
Solo `phase == "play"` cuenta para stats de rendimiento (FPS, perf, low-fps incidents).

**Campo nuevo `events`** (lista, nivel raíz del heartbeat, junto a `player`). Cola en ANNAV2
(`ANNAV2.emit_event(type, data := {})`); cada heartbeat enviado drena la cola. Cada evento:
`{"seq": int (monótono por sesión, desde 1), "t": unix_ms, "type": str, "scene": str, "data": {...}}`.
Si hay eventos pendientes al volverse idle, el flush final los lleva.
Tipos:
- `session_start` — primer heartbeat del proceso. data: `{boot_ms}` (ticks_msec hasta el primer
  heartbeat) — opcional.
- `scene_enter` — SceneManager completó una transición. data: `{from, to, load_ms}` (load_ms =
  elapsed_ms de la etapa `completed`).
- `death` — `TeleportSystem._on_player_killed`. data: `{cause?, pos: [x,y,z]}`.
- `respawn` — fin del respawn (cuando se limpia is_respawning). data: `{}`.
- `pause` / `resume` — transición de `get_tree().paused` (solo fuera de Boot/Menu).

**Central** (`odisea_central.py`):
- Procesar `events` ANTES del rate-limit de 50 ms (`_process_heartbeat`, ~l.2891) para no perderlos.
- Tabla `session_events(player_id, session_id, seq, timestamp, type, scene, data TEXT JSON,
  UNIQUE(session_id, seq))` + índices (session_id), (type, timestamp).
- Columnas nuevas en `heartbeats`: `phase TEXT`, `paused INTEGER` (migración ALTER como las demás).
- Fragmento `_PLAY_ONLY`: `COALESCE(phase, CASE WHEN scene IN ('Boot','Menu') OR COALESCE(paused,0)=1
  THEN 'x' ELSE 'play' END) = 'play'` (compat con filas viejas) — aplicarlo en TODAS las queries de
  FPS/perf donde hoy va `_FOCUSED_ONLY`, y en la detección de low-fps incidents (`_detect_low_fps_incident`).
- Broadcast de cada evento al WS `/events` del dashboard con `{"type": <event type>, "player_id",
  "session_id", "scene", "timestamp", "data"}` (reusar el mecanismo que ya emite disconnect/low_fps).
- `handle_ghosts_sessions`: sumar `deaths`, `scene_changes`, `avg_load_ms` (de session_events), y
  `play_seconds` (tiempo en phase play).
- Endpoint `GET /ghosts/sessions/{session_id}/events` → lista ordenada por seq.
- Endpoint o campo de load times: `GET /ghosts/load_times?days=N` → por escena destino: n, p50, p90
  de load_ms (desde scene_enter), + boot_ms p50/p90.
- `odisea_peer.py`: verificar que relaye `events` y `player.phase` sin perderlos (hoy preserva
  `transition`); agregar lo que falte.

**Dashboard** (`dashboard/src`):
- `types.ts`: `phase`, `paused` en PlayerState; tipos de evento.
- En vivo: si `phase != play`, mostrar badge (Boot / Menú / Cargando… con stage / Pausa) en vez de
  FPS, y NO meter esas muestras en el buffer de historia de FPS (`useTelemetry.ts` ~183).
- `EventTimeline.tsx`: consumir los eventos reales (death, scene_enter→`scene_change` con load_ms,
  session_start, pause/resume) con íconos; borrar lo que quede muerto.
- `SessionPlayback.tsx`: marcadores de muerte y cambio de escena sobre la línea de tiempo
  (fetch de `/ghosts/sessions/{id}/events`).
- `SessionHistory`/`HistoricalTable`: columnas muertes / cambios de nivel / load promedio.
- `lib/filters.ts:51`: el filtrado por nombre 'boot' queda como fallback; preferir phase.

### Ownership map
| Cluster | Archivos | Ejecutor |
|---|---|---|
| K1 juego | `core_v2/telemetry/ANNAV2*.gd`, `core_v2/autoloads/SceneManager.gd`, `core_v2/systems/TeleportSystem.gd` | Kilo DeepSeek 4.1 Flash |
| K2 central | `odisea_central.py`, `odisea_peer.py` | Kilo GLM 5.3 Flash |
| K3 dashboard | `dashboard/src/**` | Kilo DeepSeek 4.1 Flash |
| lead | `scripts/import_ghosts_to_sqlite.py` (hecho), Makefile (pendiente decisión) | — |

## Estado
- Mapeo y health check: hechos.
- K1/K2/K3 lanzados en Kilo (logs en el scratchpad de la sesión, `kilo session list`).
  Gotcha: lanzar varios `kilo run` en el mismo segundo rompe la DB de Kilo (credential update);
  espaciarlos unos segundos.
