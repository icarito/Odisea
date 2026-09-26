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

### T4 — Dashboard: navegación live↔histórico coherente + eventos en la línea de tiempo
Pedido: mejorar visibilidad; que pasar de en vivo a histórico sea coherente; que los eventos
(muerte, cambio de escena con carga, nueva sesión, pausa) se vean bien en la línea de tiempo.
Incluye mostrar `/ghosts/load_times`.

Mapa UX (Sonnet, 2026-09-26) — hallazgos clave:
- Estado en `App.tsx` `Dashboard()` (~l.1012): `activeTab` (URL `?tab=` vía
  `hooks/useUrlNavigation.ts`), `liveView` (l.1056, sin URL ni persistencia), `selectedPlayerId`
  (l.1027, a quién sigo; sin URL) vs `focusPlayerId` (l.1035, tags/notificación; en `?player=`),
  `selectedSession`/`playbackData` (l.1130, nunca se limpia → no hay "volver" en desktop).
- "Go to History" (`Viewport3D.tsx:280-303`) sobre sesión en curso → "FAILED TO LOAD SESSION DATA"
  (reproducido contra prod).
- No hay camino jugador en vivo → sus sesiones pasadas (sin filtro por player en HistoricalTable).
- EventTimeline solo en liveView 3d, en un cajón max-h-40.
- SessionPlayback (l.249-270): sin pause/resume, marcadores sin tooltip (no muestra load_ms).
- `/ghosts/load_times` no se consume. LiveCombinedChart sin marcadores de eventos.
- 19 componentes huérfanos (NavigationRail, BreadcrumbNav, DashboardTabs, Replays*, Cockpit*...).
- Capturas: fila de sesión del historial rota (columna angosta, nombre truncado "E."), etiquetas
  mezcla inglés/español, panel "Session History" en 3D en realidad muestra hotzones.
- vite.config.ts: proxy no cubre `/ghosts/*` (dev local necesita VITE_API_URL).

Plan T4 (ownership disjunto):
- **D1 navegación** (Kilo GLM 5.3) — dueño de `App.tsx`, `hooks/useUrlNavigation.ts`,
  `hooks/useLayoutPersistence*`, `Viewport3D.tsx`, `HistoricalTable.tsx`, `SessionHistory.tsx`,
  `PlayerCard.tsx`, `PlayerBottomSheet.tsx`, `ActivePlayersGrid.tsx`.
  1. Modelo de navegación único en URL: `?tab=live|mapa|heatmap|history`, `&view=dashboard|birdseye|3d`,
     `&player=<id>` (= a quién sigo; unificar selectedPlayerId/focusPlayerId: el editor de tags
     pasa a ser un estado de UI aparte que no viaja en la URL), `&session=<id>` en history.
     Back del navegador recorre esos estados (respetar la guarda PWA existente).
  2. Sesión seleccionada deseleccionable (botón volver a la lista) y deep-link.
  3. Jugador → historial: acción "Sesiones" en PlayerCard/BottomSheet/panel 3D que lleva a
     history filtrado por player_id (filtro visible y quitable en HistoricalTable). Sesión en curso
     en la lista de historial → abre live 3D siguiendo a ese jugador (no el playback).
     Reemplazar "Go to History" de Viewport3D por esa misma acción; el panel de hotzones se llama
     por lo que es.
  4. EventTimeline visible en las tres liveView para el jugador seguido (no solo 3d), con más alto.
  5. Montar `<LoadTimesPanel />` (lo crea D2) en History.
  6. Arreglar el layout de la fila de sesión en History (captura 03) y unificar etiquetas al
     español neutro en los archivos propios.
- **D2 línea de tiempo** (Kilo DeepSeek 4.1) — dueño de `SessionPlayback.tsx`,
  `EventTimeline.tsx`, `LiveCombinedChart.tsx`, `api.ts`, nuevo `components/LoadTimesPanel.tsx`.
  1. SessionPlayback: banda semitransparente pause→resume; tooltip/label en marcadores (escena
     destino + load_ms; muerte con posición); lista de eventos bajo el gráfico, clic = saltar el
     cursor del playback a ese instante.
  2. LiveCombinedChart: prop opcional `events` → mismos marcadores sobre el gráfico en vivo.
  3. EventTimeline: agrupar por sesión, hora relativa, ícono+color coherente con los marcadores.
  4. `getLoadTimes(days)` en api.ts + `LoadTimesPanel` (tabla chica: escena, n, p50, p90; fila de
     arranque boot_ms), sin props obligatorias.
- D3 HECHO (sin commit): 10 huérfanos borrados + proxy `/ghosts`. PERO el criterio correcto es
  alcanzabilidad desde `src/main.tsx` (sw.ts y globe-preview.tsx son entradas propias): quedan
  ~32 archivos inalcanzables, incluidos PlayerCard, SessionHistory, ActivePlayersGrid (editados por
  K3 en vano), AppShell/NavigationRail/BreadcrumbNav, SceneDetail/ScenesIndex, Hotzone*, Tag*,
  hooks/useWebSocket. Rehacer el análisis de alcance cuando D1/D2 terminen y borrar lo que siga
  inalcanzable (script de alcance: seguir imports relativos desde main.tsx).
- **D3 limpieza** (Sonnet) — borrar los componentes huérfanos confirmando 0 imports;
  `vite.config.ts` proxy para `/ghosts`.

### T5 — Versión como "nightly #749" en vez del hash
El heartbeat ya trae `build_id: '749'`, `build_channel: 'nightly'`, `game_version:
'0.5.0-nightly.749+ad11b29 (2026-09-26)'` (verificado en /status de prod). Solo dashboard: mostrar
canal como tag y `#<build_id>` como versión; hash solo en detalle/tooltip.

### T6 — Web: navegador y OS
Juego: `render_diag.user_agent` en ANNAV2_Thread_Web.gd (commit feat(telemetry) user_agent). El
central ya persiste render_diag (odisea_central.py:3666). Dashboard: derivar "Firefox/Chromium/
Safari · Linux/Windows/macOS/Android/iOS" del UA (regex simple, sin dependencias).

### T7 — ¿Funciona etiquetar IDs? — investigar (player_tags en central; TagPicker/
TaggableEntityEditor figuraban como inalcanzables desde main.tsx).

### T8 — Tiempos en segundos, no ms, en todo el dashboard (load_ms, boot_ms, p50/p90, latency).

Los cuatro tocan App.tsx → esperan a que D1 termine; un solo agente.

### T4-T8 — HECHO y desplegado (2026-09-26)
Commits 95f754e1 (línea de tiempo + load times), 388b3d8a (navegación en URL), 211032a3 (versión
canal #build, UA navegador/OS, segundos, borra 33 inalcanzables). `make deploy-dashboard` x2 OK
(central prod == HEAD b3092697). T7: tags funcionan (probado POST/DELETE en prod); el editor real es
PlayerTagEditor; TagPicker & co. eran un prototipo nunca montado (borrado).
Pendientes/ideas: historial dominado por canal dev (181/200 en 36 h) → ¿default nightly+release?;
/ghosts/sessions tarda 5.2 s (agente gateway); load times prod: RingHub_Level p50 51 s / p90 204 s,
boot p50 12.9 s; build_id y user_agent no están en las filas de /ghosts/sessions (MAX(build_id) en
la query si hace falta); marcadores del gráfico en vivo aproximados (PlayerHistory sin timestamps).

### T9 — Historial: canal + velocidad de /ghosts/sessions — HECHO y desplegado
99602e2b + fc665e5a. Dos pasos (recorrido streaming por idx_heartbeats_timestamp → agregar solo
candidatas), param `channels` antes del límite (vacío=dev), build_id por fila, chips
Nightly/Release/Dev (default nightly+release). Local (copia prod): ~300 ms / nightly+release
460-650 ms, exacto vs query vieja. **Prod medido: 1.1-1.6 s sin filtro, 1.3-3.4 s con filtro**
(antes 5.2 s / 6 s): prod es ~3x más lento que local. Siguiente escalón si hace falta: tabla
resumen `sessions` mantenida por _db_worker (coordinar con scripts/aggregate_and_prune_heartbeats.py
del otro agente).

## Estado
- Mapeo y health check: hechos.
- T1+T2 HECHO y commiteado: 12f29935 (juego), b3092697 (central), 8691ea09 (dashboard),
  0b6ade17 (tests bridge: 41 ok; test_auth/test_ratelimit necesitan central vivo, preexistentes).
  tests/bridge NO corre en ningún workflow de CI. Falta deploy central+dashboard (bloqueado por
  decisión de backups/disco).
- Gotcha K2: si falta una columna, /ghosts/sessions traga la excepción y devuelve [] en silencio.
- (histórico) K1/K2/K3 lanzados en Kilo (logs en el scratchpad de la sesión, `kilo session list`).
  Gotcha: lanzar varios `kilo run` en el mismo segundo rompe la DB de Kilo (credential update);
  espaciarlos unos segundos.
