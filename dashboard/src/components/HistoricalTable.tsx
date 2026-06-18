import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ChevronDown, ChevronRight, ChevronUp, Tag, Download, Play } from 'lucide-react';
import { PLATFORM_META } from './PlatformFilter';
import { getPlatform } from '../lib/filters';
import { buildLabel } from '../lib/buildLabels';

// One key/value cell used inside the expanded session-detail grid.
const SessionMeta = ({ label, value }: { label: string; value: ReactNode }) => (
  <div className="flex min-w-0 flex-col">
    <span className="text-[0.5rem] uppercase tracking-wide text-text-muted">{label}</span>
    <span className="truncate text-[0.625rem] text-text-primary">{value}</span>
  </div>
);

export const HistoricalTable = ({ sessions, onSelectSession, selectedSessionId, onEditTag, hotzonesBySession, onDownloadHotzone, onPlayHotzone }: { sessions: any[], onSelectSession: (s: any) => void, selectedSessionId?: string | null, onEditTag?: (playerId: string) => void, hotzonesBySession?: Record<string, any[]>, onDownloadHotzone?: (hotzoneId: string, label?: string) => void, onPlayHotzone?: (hotzoneId: string) => void }) => {
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

  const sortedSessions = useMemo(() => {
    return [...sessions].sort((a, b) => {
      // Live sessions always pinned to the top, regardless of sort field.
      if (!!a.live !== !!b.live) return a.live ? -1 : 1;
      const aValue = sortKey === 'date' ? Number(a.start_time) || 0 : Number(a.avg_fps) || 0;
      const bValue = sortKey === 'date' ? Number(b.start_time) || 0 : Number(b.avg_fps) || 0;
      return sortDir === 'desc' ? bValue - aValue : aValue - bValue;
    });
  }, [sessions, sortDir, sortKey]);

  // Infinite scroll: render a growing window of rows so a long history doesn't
  // mount hundreds of nodes at once. A sentinel at the bottom grows the window
  // via IntersectionObserver as the user scrolls.
  const PAGE = 30;
  const [visibleCount, setVisibleCount] = useState(PAGE);
  const sentinelRef = useRef<HTMLDivElement>(null);
  // Reset the window to the top when the sort/filter changes. Tracked in state
  // (React's "adjust state during render" pattern) so it costs no extra render
  // and stays clear of effect/ref lint rules.
  const windowSignature = `${sortKey}|${sortDir}|${sessions.length}`;
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
    if (!ts) return 'Unknown date';
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
      <div className="sticky top-0 z-10 flex items-center justify-between border-4 border-black bg-black px-3 py-2 text-[0.625rem] font-black uppercase text-accent">
        <span>Historical Sessions</span>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setSortKey(sortKey === 'date' ? 'fps' : 'date')}
            className="text-accent"
            aria-label="Toggle sort field"
          >
            {sortKey === 'date' ? 'Date' : 'FPS'}
          </button>
          <button
            type="button"
            onClick={() => setSortDir(sortDir === 'desc' ? 'asc' : 'desc')}
            className="flex items-center gap-1 text-accent"
            aria-label="Toggle sort order"
          >
            {sortDir === 'desc' ? <ChevronDown size={14} /> : <ChevronUp size={14} />}
          </button>
        </div>
      </div>

      {sessions.length === 0 ? (
        <div className="border-x-4 border-b-4 border-black bg-bg-primary/50 p-10 text-center text-xs italic text-text-muted">
          No historical sessions found
        </div>
      ) : (
        <div className="flex flex-col gap-2 border-x-4 border-b-4 border-black bg-bg-primary/40 p-2 sm:p-3">
          {visibleSessions.map((s, idx) => {
            const avgFps = Number(s.avg_fps) || 0;
            const tone = perfTone(avgFps);
            const scenesVisited = sceneCount(s.scenes_visited);
            const isSelected = selectedSessionId && s.session_id === selectedSessionId;
            const official = s.official_build === 1 || s.intake_mode === 'admin' || s.intake_mode === 'ingest';
            const versionLabel = buildLabel(s);
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
                className={`flex w-full cursor-pointer items-center gap-3 border-2 p-3 text-left shadow-[2px_2px_0px_0px_black] transition-colors sm:p-4 ${
                  isSelected ? 'border-accent bg-accent/10' : 'border-black bg-bg-card hover:bg-accent/5'
                } ${isExpanded ? 'border-b-0 shadow-none' : ''}`}
              >
                {s.live ? (
                  <span className="h-3 w-3 shrink-0 animate-pulse rounded-full bg-success shadow-[0_0_8px_rgba(63,185,80,0.6)]" title="Live" />
                ) : (
                  <span className={`h-4 w-4 shrink-0 rounded-full border-2 border-black ${tone.dot}`} />
                )}
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-2 truncate text-xs font-black text-text-primary sm:text-sm">
                    {s.live && <span className="shrink-0 bg-success px-1 text-[0.5rem] font-black uppercase text-black">Live</span>}
                    <span className="truncate">{label || (s.live ? 'En curso' : formatDate(Number(s.start_time) || 0))}</span>
                  </span>
                  <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[0.625rem] text-text-muted">
                    {s.display_name && (
                      <>
                        <span className="font-mono">{s.player_id}</span>
                        <span className="text-text-muted/60">·</span>
                      </>
                    )}
                    {!s.display_name && !s.live && (
                      <>
                        <span>{formatDate(Number(s.start_time) || 0)}</span>
                        <span className="text-text-muted/60">·</span>
                      </>
                    )}
                    {(() => {
                      const plat = getPlatform(s);
                      const meta = plat ? PLATFORM_META[plat] : undefined;
                      return (
                        <span className="inline-flex items-center gap-1 uppercase">
                          {meta?.icon}
                          {meta?.label || plat || 'unknown'}
                        </span>
                      );
                    })()}
                    <span className="text-text-muted/60">·</span>
                    {s.live ? (
                      <span className="text-success">
                        {formatDuration(Math.max(0, nowSec - (Number(s.start_time) || nowSec)))} uptime
                      </span>
                    ) : (
                      <span>{formatDuration(Number(s.duration) || 0)} played</span>
                    )}
                    <span className="text-text-muted/60">·</span>
                    <span>{scenesVisited} scenes</span>
                    {location && (
                      <>
                        <span className="text-text-muted/60">·</span>
                        <span>{location}</span>
                      </>
                    )}
                    <span className="text-text-muted/60">·</span>
                    <span className={official ? 'text-success' : 'text-warning'}>{official ? 'official' : 'canary'}</span>
                    {versionLabel && (
                      <>
                        <span className="text-text-muted/60">·</span>
                        <span>{versionLabel}</span>
                      </>
                    )}
                  </span>
                </span>
                <span className={`shrink-0 border-2 px-2 py-1 text-[0.625rem] font-black ${tone.badge}`}>
                  {avgFps.toFixed(1)}
                </span>
                {onPlayHotzone && sessionHotzones.length > 0 && (
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); onPlayHotzone(sessionHotzones[0].id); }}
                    className="shrink-0 border-2 border-success bg-success/10 p-1 text-success hover:bg-success hover:text-black"
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
                    className="shrink-0 border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
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
                    className="shrink-0 border-2 border-black bg-bg-card p-1 hover:bg-accent hover:text-black"
                    title={label ? `Editar tag de ${label}` : 'Asignar tag'}
                    aria-label="Editar tag del player"
                  >
                    <Tag size={14} />
                  </button>
                )}
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); setExpandedRow(isExpanded ? null : rowKey); }}
                  className="shrink-0 border-2 border-black bg-bg-card p-1 text-text-muted hover:bg-accent hover:text-black"
                  title={isExpanded ? 'Ocultar detalle' : 'Ver detalle'}
                  aria-expanded={isExpanded}
                  aria-label={isExpanded ? 'Ocultar detalle de la sesión' : 'Ver detalle de la sesión'}
                >
                  {isExpanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                </button>
              </div>
              {isExpanded && (
                <div className={`border-2 border-t-0 bg-bg-primary/40 px-3 py-2 sm:px-4 ${isSelected ? 'border-accent' : 'border-black'}`}>
                  <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-3">
                    <SessionMeta label="Escena(s)" value={scenesVisited} />
                    <SessionMeta label="Plataforma" value={platMeta?.label || plat || 'unknown'} />
                    <SessionMeta label="Avg FPS" value={avgFps.toFixed(1)} />
                    <SessionMeta
                      label={s.live ? 'Uptime' : 'Duración'}
                      value={s.live
                        ? formatDuration(Math.max(0, nowSec - (Number(s.start_time) || nowSec)))
                        : formatDuration(Number(s.duration) || 0)}
                    />
                    <SessionMeta label="Inicio" value={formatDate(Number(s.start_time) || 0)} />
                    <SessionMeta label="Build" value={official ? 'official' : 'canary'} />
                    {versionLabel && <SessionMeta label="Versión" value={versionLabel} />}
                    {location && <SessionMeta label="Ubicación" value={location} />}
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
