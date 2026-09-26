import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ChevronDown, ChevronRight, ChevronUp, Tag, Download, Play, X } from 'lucide-react';
import { PLATFORM_META } from './PlatformFilter';
import { getPlatform, formatSeconds } from '../lib/filters';
import { buildVersionInfo } from '../lib/buildLabels';

// One key/value cell used inside the expanded session-detail grid.
const SessionMeta = ({ label, value }: { label: string; value: ReactNode }) => (
  <div className="flex min-w-0 flex-col">
    <span className="text-[0.5rem] uppercase tracking-wide text-text-muted">{label}</span>
    <span className="truncate text-[0.625rem] text-text-primary">{value}</span>
  </div>
);

export const HistoricalTable = ({ sessions, onSelectSession, selectedSessionId, playerFilter, onClearPlayerFilter, onEditTag, hotzonesBySession, onDownloadHotzone, onPlayHotzone }: { sessions: any[], onSelectSession: (s: any) => void, selectedSessionId?: string | null, playerFilter?: string | null, onClearPlayerFilter?: () => void, onEditTag?: (playerId: string) => void, hotzonesBySession?: Record<string, any[]>, onDownloadHotzone?: (hotzoneId: string, label?: string) => void, onPlayHotzone?: (hotzoneId: string) => void }) => {
  const [sortDir, setSortDir] = useState<'desc' | 'asc'>('desc');
  const [sortKey, setSortKey] = useState<'date' | 'fps'>('date');
  // Per-row expand state (in-place metadata detail). Keyed by session id|idx so
  // it survives re-sorts; the chevron toggles it without opening the replay.
  const [expandedRow, setExpandedRow] = useState<string | null>(null);
  // Ticks every second so live-session uptime counts up in real time.
  const [nowSec, setNowSec] = useState(() => Date.now() / 1000);
  useEffect(() => {
    const hasLive = sessions.some((s) => s.live);
    if (!hasLive) return;
    const id = setInterval(() => setNowSec(Date.now() / 1000), 1000);
    return () => clearInterval(id);
  }, [sessions]);

  // Filtro por player (acción "Sesiones" desde una tarjeta de player): visible
  // y quitable desde el header de la tabla.
  const filteredSessions = useMemo(() => (
    playerFilter ? sessions.filter((s) => s.player_id === playerFilter) : sessions
  ), [sessions, playerFilter]);

  const sortedSessions = useMemo(() => {
    return [...filteredSessions].sort((a, b) => {
      // Live sessions always pinned to the top, regardless of sort field.
      if (!!a.live !== !!b.live) return a.live ? -1 : 1;
      const aValue = sortKey === 'date' ? Number(a.start_time) || 0 : Number(a.avg_fps) || 0;
      const bValue = sortKey === 'date' ? Number(b.start_time) || 0 : Number(b.avg_fps) || 0;
      return sortDir === 'desc' ? bValue - aValue : aValue - bValue;
    });
  }, [filteredSessions, sortDir, sortKey]);

  // Infinite scroll: render a growing window of rows so a long history doesn't
  // mount hundreds of nodes at once. A sentinel at the bottom grows the window
  // via IntersectionObserver as the user scrolls.
  const PAGE = 30;
  const [visibleCount, setVisibleCount] = useState(PAGE);
  const sentinelRef = useRef<HTMLDivElement>(null);
  // Reset the window to the top when the sort/filter changes. Tracked in state
  // (React's "adjust state during render" pattern) so it costs no extra render
  // and stays clear of effect/ref lint rules.
  const windowSignature = `${sortKey}|${sortDir}|${filteredSessions.length}|${playerFilter || ''}`;
  const [lastSignature, setLastSignature] = useState(windowSignature);
  if (lastSignature !== windowSignature) {
    setLastSignature(windowSignature);
    setVisibleCount(PAGE);
  }
  const visibleSessions = useMemo(
    () => sortedSessions.slice(0, visibleCount),
    [sortedSessions, visibleCount],
  );
  const hasMore = visibleCount < sortedSessions.length;
  useEffect(() => {
    if (!hasMore) return;
    const el = sentinelRef.current;
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        setVisibleCount((c) => Math.min(c + PAGE, sortedSessions.length));
      }
    }, { rootMargin: '200px' });
    io.observe(el);
    return () => io.disconnect();
  }, [hasMore, sortedSessions.length]);

  const formatDate = (ts: number) => {
    if (!ts) return 'Sin fecha';
    const parts = new Intl.DateTimeFormat('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(new Date(ts * 1000));
    const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    return `${byType.day} ${byType.month} ${byType.year} ${byType.hour}:${byType.minute}`;
  };

  const formatDuration = (seconds: number) => {
    const safe = Math.max(0, Math.round(Number(seconds) || 0));
    const minutes = Math.floor(safe / 60);
    const secs = safe % 60;
    return minutes > 0 ? `${minutes}m ${secs}s` : `${secs}s`;
  };

  const perfTone = (fps: number) => {
    if (fps > 45) return {
      dot: 'bg-green-500',
      badge: 'bg-green-500/15 text-green-300 border-green-500',
    };
    if (fps >= 30) return {
      dot: 'bg-yellow-500',
      badge: 'bg-yellow-500/15 text-yellow-300 border-yellow-500',
    };
    return {
      dot: 'bg-red-500',
      badge: 'bg-red-500/15 text-red-300 border-red-500',
    };
  };

  const sceneCount = (value: any) => {
    if (Array.isArray(value)) return value.length;
    if (typeof value === 'string') return value.split(',').filter(Boolean).length || Number(value) || 0;
    return Number(value) || 0;
  };

  return (
    <div className="w-full font-mono">
      <div className="sticky top-0 z-10 flex items-center justify-between gap-2 border-4 border-black bg-black px-3 py-2 text-[0.625rem] font-black uppercase text-accent">
        <div className="flex min-w-0 items-center gap-2">
          <span className="truncate">Sesiones{filteredSessions.length ? ` (${filteredSessions.length})` : ''}</span>
          {playerFilter && (
            <button
              type="button"
              onClick={onClearPlayerFilter}
              className="flex shrink-0 items-center gap-1 border border-accent/60 px-1 text-[0.5rem] font-black uppercase text-accent hover:bg-accent hover:text-black"
              title="Quitar filtro de player"
              aria-label="Quitar filtro de player"
            >
              {playerFilter.slice(0, 8)}
              <X size={10} />
            </button>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={() => setSortKey(sortKey === 'date' ? 'fps' : 'date')}
            className="text-accent"
            aria-label="Cambiar campo de orden"
          >
            {sortKey === 'date' ? 'Fecha' : 'FPS'}
          </button>
          <button
            type="button"
            onClick={() => setSortDir(sortDir === 'desc' ? 'asc' : 'desc')}
            className="flex items-center gap-1 text-accent"
            aria-label="Cambiar orden"
          >
            {sortDir === 'desc' ? <ChevronDown size={14} /> : <ChevronUp size={14} />}
          </button>
        </div>
      </div>

      {filteredSessions.length === 0 ? (
        <div className="border-x-4 border-b-4 border-black bg-bg-primary/50 p-10 text-center text-xs italic text-text-muted">
          {playerFilter ? 'Sin sesiones de este player' : 'Sin sesiones históricas'}
        </div>
      ) : (
        <div className="flex flex-col gap-2 border-x-4 border-b-4 border-black bg-bg-primary/40 p-2 sm:p-3">
          {visibleSessions.map((s, idx) => {
            const avgFps = Number(s.avg_fps) || 0;
            // Solo lo traen las filas vivas fusionadas (ver el merge en App.tsx).
            const fpsNow = s.fps_now == null ? null : Number(s.fps_now);
            const tone = perfTone(avgFps);
            const scenesVisited = sceneCount(s.scenes_visited);
            const isSelected = selectedSessionId && s.session_id === selectedSessionId;
            const official = s.official_build === 1 || s.intake_mode === 'admin' || s.intake_mode === 'ingest';
            const version = buildVersionInfo(s);
            const label = s.display_name || '';
            const location = [s.city, s.country_code || s.country].filter(Boolean).join(', ');
            const sessionHotzones = (s.session_id && hotzonesBySession?.[s.session_id]) || [];
            const rowKey = `${s.session_id || 'session'}-${idx}`;
            const isExpanded = expandedRow === rowKey;
            const plat = getPlatform(s);
            const platMeta = plat ? PLATFORM_META[plat] : undefined;
            return (
              <div key={rowKey} className="flex flex-col">
              <div
                role="button"
                tabIndex={0}
                onClick={() => onSelectSession(s)}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelectSession(s); } }}
                className={`flex w-full cursor-pointer flex-col gap-1 border-2 p-2 text-left shadow-[2px_2px_0px_0px_black] transition-colors sm:p-3 ${
                  isSelected ? 'border-accent bg-accent/10' : 'border-black bg-bg-card hover:bg-accent/5'
                } ${isExpanded ? 'border-b-0 shadow-none' : ''}`}
              >
                {/* Fila 1: estado + nombre (ancho completo, sin truncar a nada) + FPS. */}
                <div className="flex items-center gap-2">
                  {s.live ? (
                    <span className="h-3 w-3 shrink-0 animate-pulse rounded-full bg-success shadow-[0_0_8px_rgba(63,185,80,0.6)]" title="En vivo" />
                  ) : (
                    <span className={`h-4 w-4 shrink-0 rounded-full border-2 border-black ${tone.dot}`} />
                  )}
                  <span className="min-w-0 flex-1 truncate text-xs font-black text-text-primary sm:text-sm">
                    {label || (s.live ? 'En curso' : formatDate(Number(s.start_time) || 0))}
                  </span>
                  {s.live && <span className="shrink-0 bg-success px-1 text-[0.5rem] font-black uppercase text-black">En vivo</span>}
                  <span className="flex shrink-0 items-center gap-1">
                    {s.live && fpsNow != null && (
                      <span className="text-[0.5625rem] font-mono text-text-muted" title="FPS ahora mismo">
                        {fpsNow.toFixed(0)} ahora
                      </span>
                    )}
                    {/* El badge es SIEMPRE el promedio de la sesion, viva o no. En una sesion
                        viva el valor del instante va al lado y se lee como tal: mezclarlos en
                        el mismo numero era justo la ambiguedad -- ordenar por FPS comparaba
                        promedios contra fotos de un frame. */}
                    <span className={`border-2 px-2 py-1 text-[0.625rem] font-black ${tone.badge}`} title="FPS promedio de la sesión">
                      {avgFps.toFixed(1)}
                    </span>
                  </span>
                </div>
                {/* Fila 2: metadatos, con wrap propio para no aplastar el nombre. */}
                <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[0.625rem] text-text-muted">
                  {s.live ? (
                    <span className="text-success">
                      {formatDuration(Math.max(0, nowSec - (Number(s.start_time) || nowSec)))} activo
                    </span>
                  ) : (
                    <span>{formatDate(Number(s.start_time) || 0)}</span>
                  )}
                  <span className="text-text-muted/60">·</span>
                  <span>{formatDuration(Number(s.duration) || 0)} jugado</span>
                  <span className="text-text-muted/60">·</span>
                  <span>{scenesVisited} escenas</span>
                  <span className="text-text-muted/60">·</span>
                  <span className="inline-flex items-center gap-1 uppercase">
                    {platMeta?.icon}
                    {platMeta?.label || plat || 'desconocida'}
                  </span>
                  {s.deaths != null && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span>{Number(s.deaths) || 0} muertes</span>
                    </>
                  )}
                  {s.scene_changes != null && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span>{Number(s.scene_changes) || 0} cambios</span>
                    </>
                  )}
                  {s.avg_load_ms != null && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span>{formatSeconds(s.avg_load_ms)} carga</span>
                    </>
                  )}
                  {location && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span>{location}</span>
                    </>
                  )}
                  <span className="text-text-muted/60">·</span>
                  <span className={official ? 'text-success' : 'text-warning'}>{official ? 'official' : 'canary'}</span>
                  {version && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span title={version.hash ? `commit ${version.hash}` : undefined}>
                        <span className="uppercase">{version.channel}</span>
                        {version.version ? ` ${version.version}` : ''}
                      </span>
                    </>
                  )}
                  {s.player_id && (
                    <>
                      <span className="text-text-muted/60">·</span>
                      <span className="font-mono">{s.player_id}</span>
                    </>
                  )}
                </div>
                {/* Fila 3: acciones, alineadas a la derecha. */}
                <div className="flex items-center justify-end gap-1">
                  {onPlayHotzone && sessionHotzones.length > 0 && (
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); onPlayHotzone(sessionHotzones[0].id); }}
                      className="border-2 border-success bg-success/10 p-1 text-success hover:bg-success hover:text-black"
                      title={`Reproducir hotzone${sessionHotzones.length > 1 ? ` (1 de ${sessionHotzones.length})` : ''}`}
                      aria-label="Reproducir hotzone de la sesión"
                    >
                      <Play size={14} fill="currentColor" />
                    </button>
                  )}
                  {onDownloadHotzone && sessionHotzones.length > 0 && (
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); onDownloadHotzone(sessionHotzones[0].id, label || s.player_id); }}
                      className="border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
                      title={`Descargar hotzone${sessionHotzones.length > 1 ? ` (1 de ${sessionHotzones.length})` : ''}`}
                      aria-label="Descargar hotzone de la sesión"
                    >
                      <Download size={14} />
                    </button>
                  )}
                  {onEditTag && s.player_id && (
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); onEditTag(s.player_id); }}
                      className="border-2 border-black bg-bg-card p-1 hover:bg-accent hover:text-black"
                      title={label ? `Editar tag de ${label}` : 'Asignar tag'}
                      aria-label="Editar tag del player"
                    >
                      <Tag size={14} />
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); setExpandedRow(isExpanded ? null : rowKey); }}
                    className="border-2 border-black bg-bg-card p-1 text-text-muted hover:bg-accent hover:text-black"
                    title={isExpanded ? 'Ocultar detalle' : 'Ver detalle'}
                    aria-expanded={isExpanded}
                    aria-label={isExpanded ? 'Ocultar detalle de la sesión' : 'Ver detalle de la sesión'}
                  >
                    {isExpanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                  </button>
                </div>
              </div>
              {isExpanded && (
                <div className={`border-2 border-t-0 bg-bg-primary/40 px-3 py-2 sm:px-4 ${isSelected ? 'border-accent' : 'border-black'}`}>
                  <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-3">
                    <SessionMeta label="Escena(s)" value={scenesVisited} />
                    <SessionMeta label="Plataforma" value={platMeta?.label || plat || 'desconocida'} />
                    <SessionMeta label="FPS prom." value={avgFps.toFixed(1)} />
                {s.live && fpsNow != null && (
                  <SessionMeta label="FPS ahora" value={fpsNow.toFixed(0)} />
                )}
                    <SessionMeta
                      label={s.live ? 'Activo' : 'Duración'}
                      value={s.live
                        ? formatDuration(Math.max(0, nowSec - (Number(s.start_time) || nowSec)))
                        : formatDuration(Number(s.duration) || 0)}
                    />
                    <SessionMeta label="Inicio" value={formatDate(Number(s.start_time) || 0)} />
                    <SessionMeta label="Canal" value={official ? 'official' : 'canary'} />
                    {version && (
                      <SessionMeta
                        label="Build"
                        value={`${version.channel}${version.version ? ` ${version.version}` : ''}${version.hash ? ` (${version.hash})` : ''}`}
                      />
                    )}
                    {location && <SessionMeta label="Ubicación" value={location} />}
                    {s.deaths != null && <SessionMeta label="Muertes" value={String(Number(s.deaths) || 0)} />}
                    {s.scene_changes != null && <SessionMeta label="Cambios de escena" value={String(Number(s.scene_changes) || 0)} />}
                    {s.avg_load_ms != null && <SessionMeta label="Carga promedio" value={formatSeconds(s.avg_load_ms)} />}
                    {s.player_id && <SessionMeta label="Player ID" value={s.player_id} />}
                    {s.session_id && <SessionMeta label="Sesión" value={String(s.session_id).slice(0, 12)} />}
                    {sessionHotzones.length > 0 && <SessionMeta label="Hotzones" value={sessionHotzones.length} />}
                  </div>
                </div>
              )}
              </div>
            );
          })}
          {/* Infinite-scroll sentinel + remaining count. */}
          {hasMore && (
            <div ref={sentinelRef} className="py-2 text-center text-[0.625rem] uppercase tracking-widest text-text-muted">
              Cargando más… ({sortedSessions.length - visibleCount} restantes)
            </div>
          )}
        </div>
      )}
    </div>
  );
};
