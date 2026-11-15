# FD-315: Discord Rich Presence con datos de telemetría en vivo

**Status:** Planned
**Priority:** P2
**Effort:** Medium
**Created:** 2026-09-22
**Parent:** — (nuevo, sin relación con FD-032/314)
**Relacionadas:** `core_v2/telemetry/ANNAV2.gd` · `core_v2/autoloads/SessionManager.gd` · `core_v2/autoloads/PerformanceMonitor.gd` · `core_v2/autoloads/SettingsManager.gd` · `docs/features/FD-292_telemetry_first_run_consent.md`

---

## 1. Resumen y Contexto

Sebastián quiere que Odisea exponga **Discord Rich Presence** cuando el jugador
juegue con Discord abierto. El presence no debe quedarse en el estático "Jugando
Odisea": la idea de producto es que **exponga datos de la telemetría en vivo**
(zona actual, sesión #, FPS) para reforzar el ángulo de plataforma/EducaJuegos:
cada partida se ve desde afuera como una sesión viva de trabajo/exploración, no
como un juego genérico.

**Por qué ahora:** el proyecto ya tiene telemetría client-side consolidada
(`ANNAV2.gd`), consentimiento first-run (FD-292) y un `PerformanceMonitor`
autoload que calcula FPS en vivo. Rich Presence reutiliza esas fuentes ya
verificadas; no inventa un pipeline nuevo.

---

## 2. Objetivos

- **O1. Presence vivo**: la tarjeta de Discord muestra estado real del juego —
  zona/área actual, número de sesión del jugador y FPS — no un texto estático.
- **O2. Reutilizar telemetría**: los datos salen de las fuentes ya existentes
  (`ANNAV2`, `SessionManager`, `PerformanceMonitor`); no se duplica lógica de
  captura.
- **O3. Privacidad por defecto**: el presence respeta el mismo consentimiento de
  telemetría (FD-292) y tiene opt-out propio. Sin consentimiento → presencia
  mínima ("Jugando Odisea") o nula, según lo que defina Sebastián.
- **O4. Bajo costo**: el update rate respeta los límites de la API de Discord
  (15s mínimo entre updates en presence, sin spam). En low-end no afecta FPS.
- **O5. Sin tocar el core de determinismo/replay**: Rich Presence es solo
  lectura de estado + SDK; no participa del `replay_sync` ni del snapshot.

**Fuera de scope (backlog):**
- Actividad en el perfil (user-set status), botones clickeables en la tarjeta,
  joins/spectate/invite (multiplayer real).
- Integración con el backend central de telemetría (dashboard): el presence se
  alimenta **solo** de datos client-side ya disponibles.
- Soporte para consolas u otras plataformas que no sean Discord desktop/web.
- Cambios al consentimiento de FD-292 ni al flujo first-run existente (solo se
  lee).

---

## 3. Estado actual verificado

| Ítem | Dónde | Detalle |
|---|---|---|
| Telemetría client | `core_v2/telemetry/ANNAV2.gd` | autoload; recolecta a 10Hz (`TELEMETRY_INTERVAL_MS=100`); expone `_session_id`, `_player_id`, `_build_info`; desactivable; no emite en replay (`_is_hotzone_playback`) |
| Consentimiento | `core_v2/autoloads/SettingsManager.gd` | flags `consent_asked`, `error_reports_enabled` etc. en sección `privacy`; `needs_privacy_consent()`; flujo first-run FD-292 |
| FPS en vivo | `core_v2/autoloads/PerformanceMonitor.gd` | `Performance.get_monitor(Performance.TIME_FPS)` cacheado; señal `lag_spike_detected` |
| Zona/área actual | `core_v2/autoloads/AudioManager.gd` | `register_zone`/`unregister_zone`, `_active_zone` priorizado por volumen — no es un "nivel actual" semántico; fuente candidata, ver §4.2 |
| Escena actual | `core_v2/autoloads/SessionManager.gd` | `get_tree().current_scene` usado en varios puntos |
| SDK Discord | — | **no existe** ningún plugin/GDExtension de Discord en el repo hoy (verificado: `plugins/` vacío, sin referencias a `discord` en `project.godot`) |

**Nota:** la "zona actual" semántica del jugador (p.ej. `Dome_Intro`,
`RingHub_Level`) hoy no está expuesta como un getter central limpio; el candidato
más estable es la escena actual (`current_scene.filename`) o, si se quiere el
nombre de zona lógica, un helper nuevo que derive nombre legible de la escena.
El FD no introduce un sistema de zonas nuevo: usa lo que ya existe y documenta
la fuente elegida.

---

## 4. Diseño

### 4.1 Arquitectura

```
Godot (core_v2)                        Discord
┌────────────────────────────┐         ┌─────────────────┐
│ ANNAV2 (telemetría 10Hz) ──┼──datos──▶ DiscordPresence │
│ SessionManager            ─┼────────▶ (autoload nuevo) │
│ PerformanceMonitor (FPS)  ─┼──set───▶  SDK/GDExtension │
│ SettingsManager (consent) ─┼─gate───▶  set_activity()  │
└────────────────────────────┘         └─────────────────┘
```

- **`DiscordPresence.gd`** (autoload nuevo, `core_v2/autoloads/`): único punto
  de contacto con el SDK. Lee estado de los autoloads existentes, arma el
  `Activity` y llama al SDK respetando el rate limit (15s mínimo).
- **SDK**: GDExtension/plugin de Discord para Godot. **Decisión abierta** para
  Sebastián: (a) usar un plugin GDExtension de la comunidad (p.ej.
  `godot-discord-sdk` / Rich Presence SDK oficial vía GDExtension), o (b)
  implementar el handshake de IPC del Rich Presence SDK (protocolo por socket
  local, sin dependencia de plugin). El FD no fija el plugin: la fase A es un
  spike para verificar cuál integra con el pin de Godot 3.6.4-rc del fork
  `godot-box3d-3` (ver §8). **El SDK es la única dependencia nueva**; si el
  plugin no compila contra el fork, el fallback es IPC manual.

### 4.2 Datos a exponer

| Campo de la tarjeta | Fuente | Frecuencia | Notas |
|---|---|---|---|
| Detalle (línea 1) | `SessionManager` / escena actual → nombre legible de zona | cada update (≥15s) | "Explorando Dome_Intro" / "En RingHub" / "En el menú" |
| Estado (línea 2) | `ANNAV2._session_id` → "Sesión #N" | cada update | N = número de sesión del jugador (derivado de `_session_id` o contador local de `user://`) |
| FPS | `PerformanceMonitor` / `Performance.get_monitor(TIME_FPS)` | cada update | "42 FPS" — redondeado; **omito el campo si FPS no es medible** (menú/pausa) |
| Timestamps | reloj local | al iniciar sesión | `start` para "jugó hace X min"; se resetea al cambiar de zona o al volver al menú |

**Límites de la API de Discord:** el presence se actualiza como mínimo cada 15
segundos (límite real de la API; updates más frecuentes se ignoran/rate-limit).
El autoload **nunca** actualiza a 10Hz: acumula el estado más reciente y lo
empuja al SDK con throttle de 15s. En el menú o en pausa se puede degradar a un
presence estático "En el menú de Odisea".

### 4.3 Privacidad / opt-out

- **Puerta de consentimiento (FD-292)**: sin consentimiento de telemetría →
  el presence se degrada a "Jugando Odisea" (estático, sin zona/sesión/FPS).
- **Opt-out propio**: flag en `SettingsManager` (`privacy/discord_presence`,
  default ON si ya hay consentimiento) que desactiva por completo el presence
  (o lo degrada a estático — decisión de Sebastián, default propuesto: OFF
  total = sin presencia).
- **Nunca** se exponen datos del backend central ni identificadores crudos:
  el `_player_id` NO aparece en la tarjeta; solo el número de sesión derivado.
- El presence no se activa durante replays (`ANNAV2` ya no emite en
  `_is_hotzone_playback`; el presence sigue el mismo gate).

### 4.4 Casos de uso

- **Single**: presencia vivo "Explorando X · Sesión #N · 42 FPS" → el jugador
  muestra su partida sin streamear.
- **Multi/coop (futuro)**: el presence queda listo para agregar party/join
  cuando exista multiplayer real (hoy fuera de alcance, §2).
- **Educativo (EducaJuegos)**: el angle de plataforma — la tarjeta comunica
  "sesión de trabajo" (sesión #, zona) en vez de un juego genérico; refuerza
  el uso en aulas/eventos sin exponer datos personales.

### 4.5 Assets

- **Icono/arte**: se requiere el asset key de la aplicación de Discord
  (Application ID + `assets`). El arte del icono (logo de Odisea) se entrega en
  la app de Discord; no es un asset del repo. **Bloqueador externo**: Sebastián
  debe crear la aplicación en el portal de Discord y subir el asset key.
- **Sin assets en repo**: el presence usa texto + asset key; no se agregan
  imágenes al juego.

---

## 5. Archivos a modificar/crear

- `core_v2/autoloads/DiscordPresence.gd` (nuevo) — autoload; lectura de estado,
  armado de Activity, throttle 15s, gates de consentimiento/opt-out/replay.
- `core_v2/autoloads/DiscordPresenceSDK.gd` o GDExtension wrapper (nuevo) —
  capa delgada sobre el SDK/plugin (o IPC manual si el plugin no compila).
- `project.godot` — registrar autoload `DiscordPresence` (y el plugin en
  `[editor_plugins]`/dependencies si aplica).
- `core_v2/autoloads/SettingsManager.gd` (modify) — flag
  `privacy/discord_presence` + default según consentimiento.
- `core_v2/autoloads/PerformanceMonitor.gd` (modify, opcional) — getter
  público de FPS si no existe.
- Helper de nombre de zona (nuevo o en `SessionManager`) — deriva nombre
  legible de `current_scene.filename`.
- Tests: `core_v2/tests/test_discord_presence.gd` (nuevo).

---

## 6. Comportamiento y update rate

1. Al arrancar: `DiscordPresence` lee consentimiento + flag de opt-out.
2. Si habilitado y SDK disponible: conecta, `set_activity` inicial con
   timestamp `start`.
3. Cada **≥15s** (throttle): re-arma el activity con zona/sesión/FPS actuales.
4. Cambio de escena/zona → update inmediato permitido (evento de cambio, no
   spam periódico).
5. Menú/pausa → presence degradado/estático ("En el menú").
6. Sin consentimiento → estático "Jugando Odisea" (o ausente, según decisión).
7. Replay/hotzone playback → sin presence (gate de `ANNAV2`).
8. Al salir: `clear_activity`.

**Rate limit de la API:** Discord impone ~15s entre updates de presence. El
throttle del autoload es igual o mayor; nunca se llama al SDK más de una vez
por 15s salvo eventos de cambio de escena.

---

## 7. Métricas de éxito

- **Presence vivo visible**: con consentimiento ON, la tarjeta muestra
  zona/sesión/FPS y se actualiza al cambiar de zona (verificación manual con
  Discord abierto + juego corriendo).
- **Sin regresión de telemetría**: `ANNAV2` sigue emitiendo igual; el presence
  solo lee, no escribe.
- **Costo bajo**: sin aumento medible de FPS cost ni de carga en `_process`
  (el throttle de 15s limita el trabajo; medible con el `PerformanceMonitor`
  existente).
- **Privacidad**: sin consentimiento → sin datos personales en la tarjeta;
  flag de opt-out funciona y persiste en `user://`.
- **Suite de tests verde**: tests del autoload con SDK mockeado (sin llamadas
  reales a Discord en CI).

---

## 8. Plan de ejecución (fases)

| Fase | Trabajo | Resultado |
|---|---|---|
| A | Spike: elegir vía SDK (GDExtension de comunidad vs IPC manual) contra el pin 3.6.4-rc del fork `godot-box3d-3` | decisión documentada; si GDExtension no compila → IPC manual |
| B | `DiscordPresenceSDK.gd` (capa SDK/IPC) + conexión/cierre | conecta y des-conecta sin crashear |
| C | `DiscordPresence.gd`: lectura de zona/sesión/FPS, armado de Activity, throttle 15s, gates (consent/opt-out/replay) | presence vivo funcional |
| D | SettingsManager: flag `privacy/discord_presence` + wiring al menú de opciones | opt-out visible y persistente |
| E | Tests con SDK mockeado + verificación manual con Discord real | suite verde + tarjeta verificada |
| F | (Bloqueador externo, no Jules) Sebastián crea la app en el portal de Discord y sube el asset key del icono | presence con icono |

Fases A–E delegables a Jules (rama `feature/FD-315-discord-rich-presence`),
revisión por chunks; merge solo con OK explícito de Sebastián. La fase F es de
Sebastián (portal de Discord), no se delega.

**Nota de proceso (2026-09-22):** FD spec-only → entrega directa a `main` con
`[build:none]` en el commit (un FD no dispara build). Antes de pushear, verificar
que no haya un build en progreso en `main` (Odisea o engine); si lo hay, esperar
a que termine para no interrumpirlo.
