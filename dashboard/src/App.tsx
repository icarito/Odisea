import { lazy, Suspense, useState, useEffect, useMemo, useRef, useCallback, type ReactNode } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { notify } from './lib/notify';
import {
  Bar,
  BarChart,
  Brush,
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { LoginScreen } from './components/LoginScreen';
import { NotificationSettings } from './components/NotificationSettings';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { DashboardLayout } from './components/DashboardLayout';
import { PlayerBottomSheet } from './components/PlayerBottomSheet';
import { FiltersDrawer, FiltersSidebar, type SceneFilterOption, type CountryFilterOption } from './components/FiltersDrawer';
import { LiveCombinedChart } from './components/LiveCombinedChart';
import { RetroCard, RetroButton, CollapsibleCard } from './components/retro';
import { PlayerFocus } from './components/PlayerFocus';
import { PlayerTagEditor } from './components/PlayerTagEditor';
import { useTelemetry } from './hooks/useTelemetry';
import { useLayoutPersistence } from './hooks/useLayoutPersistence';
import { getGeoPlayers, getHeatmap, getHistoricalSessions, getGhostData, getScenes, getGhostStats, getHotzones, downloadHotzone, deleteHotzone, getHotzoneDownloadLink } from './api';
import {
  KNOWN_PLATFORMS,
  getPlatform,
  isDashboardSession,
  sessionScenes,
  sessionDuration,
  isUsefulSceneName,
  formatFpsLabel,
} from './lib/filters';
import { Maximize2, X, SlidersHorizontal, RotateCcw, WifiOff, Download, Trash2, Play, Tag, ChevronDown, ChevronRight } from 'lucide-react';
import type { Tab } from './types';

type GitCommit = {
  sha: string;
  date: string;
  message: string;
};

const DASHBOARD_BUILD_VERSION = (
  import.meta.env.VITE_DASHBOARD_VERSION
  || import.meta.env.VITE_GIT_COMMIT
  || ''
).slice(0, 12);
const DEFAULT_HISTORY_MIN_DURATION = 13;
const DASHBOARD_UPDATED_FLAG = 'odisea_dashboard_updated';

const loadViewport3D = () => import('./components/Viewport3D').then((module) => ({ default: module.Viewport3D }));
const Viewport3D = lazy(loadViewport3D);
const Heatmap3D = lazy(() => import('./components/Heatmap3D').then((module) => ({ default: module.Heatmap3D })));
const GlobeView = lazy(() => import('./components/GlobeView').then((module) => ({ default: module.GlobeView })));
const SessionPlayback = lazy(() => import('./components/SessionPlayback').then((module) => ({ default: module.SessionPlayback })));

const LazyPanelFallback = ({ label = 'Cargando vista…' }: { label?: string }) => (
  <div className="flex h-full min-h-0 items-center justify-center bg-bg-primary text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
    {label}
  </div>
);

const activateWaitingServiceWorker = (registration: ServiceWorkerRegistration) => {
  const waiting = registration.waiting;
  if (!waiting) return false;
  try { sessionStorage.setItem(DASHBOARD_UPDATED_FLAG, '1'); } catch { /* ignore */ }
  waiting.postMessage({ type: 'SKIP_WAITING' });
  return true;
};

const waitForInstalledWorker = (worker: ServiceWorker) => new Promise<void>((resolve) => {
  if (worker.state === 'installed') {
    resolve();
    return;
  }
  worker.addEventListener('statechange', () => {
    if (worker.state === 'installed') resolve();
  });
});

const updateDashboardWhenCached = async () => {
  if (!('serviceWorker' in navigator)) {
    try { sessionStorage.setItem(DASHBOARD_UPDATED_FLAG, '1'); } catch { /* ignore */ }
    window.location.reload();
    return;
  }

  const registration = await navigator.serviceWorker.getRegistration();
  if (!registration) return;
  if (activateWaitingServiceWorker(registration)) return;

  const updateFound = new Promise<ServiceWorker | null>((resolve) => {
    const existing = registration.installing;
    if (existing) {
      resolve(existing);
      return;
    }
    const timer = window.setTimeout(() => resolve(null), 60000);
    registration.addEventListener('updatefound', () => {
      window.clearTimeout(timer);
      resolve(registration.installing);
    }, { once: true });
  });

  await registration.update();
  if (activateWaitingServiceWorker(registration)) return;

  const worker = registration.installing || await updateFound;
  if (!worker) return;
  await waitForInstalledWorker(worker);
  activateWaitingServiceWorker(registration);
};

const formatDateTime = (timestampSeconds: number) => {
  if (!timestampSeconds) return 'No data';
  const parts = new Intl.DateTimeFormat('en-GB', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(new Date(timestampSeconds * 1000));
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${byType.day} ${byType.month} ${byType.year} ${byType.hour}:${byType.minute}`;
};

const formatPlayTime = (seconds: number) => {
  const safe = Math.max(0, Math.round(seconds || 0));
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
};

const fpsColor = (fps: number) => {
  if (fps > 45) return '#3fb950';
  if (fps >= 30) return '#d29922';
  return '#f85149';
};

// Standalone "Sessions per day" bar chart, shown in the Live top stripe when no
// player is live. Reused from the HomeStats aggregation logic.
const SessionsPerDayChart = ({ sessions }: { sessions: any[] }) => {
  const sessionsByDay = useMemo(() => {
    const grouped = new Map<string, number>();
    sessions.filter(isDashboardSession).forEach((s) => {
      const ts = Number(s.start_time) || 0;
      if (!ts) return;
      const day = new Date(ts * 1000).toISOString().slice(0, 10);
      grouped.set(day, (grouped.get(day) || 0) + 1);
    });
    return Array.from(grouped.entries())
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, count]) => ({ date, count }));
  }, [sessions]);

  const tooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div className="font-black text-accent">{d.date}</div>
        <div>Sessions: {d.count}</div>
      </div>
    );
  };

  if (sessionsByDay.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-xs italic text-text-muted">
        No session history yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
      <BarChart data={sessionsByDay} margin={{ bottom: sessionsByDay.length > 10 ? 4 : 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
        <XAxis dataKey="date" stroke="#666" fontSize={10} tickFormatter={(v) => String(v).slice(5)} />
        <YAxis stroke="#666" fontSize={10} allowDecimals={false} />
        <Tooltip content={tooltip} />
        <Bar dataKey="count" fill="#7fd1ff" isAnimationActive={false} />
        {sessionsByDay.length > 10 && (
          <Brush dataKey="date" height={16} stroke="#7fd1ff" travellerWidth={8} fill="#0d1117"
            tickFormatter={(v) => String(v).slice(5)} />
        )}
      </BarChart>
    </ResponsiveContainer>
  );
};

const countryFlag = (countryCode?: string | null): string => {
  const code = (countryCode || '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return '';
  return Array.from(code).map((char) => String.fromCodePoint(char.charCodeAt(0) + 127397)).join('');
};

// One key/value cell used inside the expanded hotzone detail grid.
const HzMeta = ({ label, value }: { label: string; value: ReactNode }) => (
  <div className="flex min-w-0 flex-col">
    <span className="text-[0.5rem] uppercase tracking-wide text-text-muted">{label}</span>
    <span className="truncate text-[0.625rem] text-text-primary">{value}</span>
  </div>
);

// Reusable hotzone captures list — performance ghosts uploaded by the game,
// ordered newest first (the API already sorts by timestamp DESC). Each row
// surfaces the scene and capture duration alongside the player + date, and
// expands in-place to show the full metadata for that capture.
const HotzoneRow = ({
  hz,
  name,
  session,
  onPlay,
  onDownload,
  onDelete,
  onTag,
  compact = false
}: {
  hz: any;
  name?: string;
  session?: any;
  onPlay?: (id: string) => void;
  onDownload?: (id: string, label: string) => void;
  onDelete?: (id: string, label: string) => void;
  onTag?: (id: string) => void;
  compact?: boolean;
}) => {
  const [expanded, setExpanded] = useState(false);
  const label = name || hz.display_name || String(hz.player_id || '').slice(0, 8);
  const when = hz.timestamp ? formatDateTime(Number(hz.timestamp)) : '';
  const scene = hz.scene || 'Escena desconocida';
  const dur = typeof hz.duration_sec === 'number'
    ? hz.duration_sec
    : (typeof hz.capture_duration === 'number' ? hz.capture_duration : null);
  const frames = hz.frame_count || null;
  const size = hz.size_kb ? `${Math.round(hz.size_kb)}KB` : null;
  const trigger = hz.trigger_type || hz.trigger || 'auto';
  const isManual = trigger === 'manual';
  const isOptimistic = hz.is_optimistic;
  // The per-frame FPS series lives inside the binary blob (not decoded here),
  // so the honest FPS context we can show is the owning session's average.
  const sessionFps = session && typeof session.avg_fps !== 'undefined' && session.avg_fps !== null
    ? Number(session.avg_fps)
    : null;
  const grid = (hz.grid_x != null && hz.grid_z != null)
    ? `${Number(hz.grid_x).toFixed(1)}, ${Number(hz.grid_z).toFixed(1)}`
    : null;

  return (
    <div className={`border-2 border-black bg-bg-primary ${isOptimistic ? 'opacity-50 grayscale' : ''}`}>
    <div className={`flex items-center justify-between gap-2 ${compact ? 'px-2 py-1' : 'px-3 py-2'}`}>
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex min-w-0 flex-1 items-center gap-1.5 text-left"
        aria-expanded={expanded}
        title={expanded ? 'Ocultar detalle' : 'Ver detalle'}
      >
        {expanded ? <ChevronDown size={compact ? 12 : 14} className="shrink-0 text-text-muted" /> : <ChevronRight size={compact ? 12 : 14} className="shrink-0 text-text-muted" />}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <div className={`truncate ${compact ? 'text-[0.625rem]' : 'text-xs'} font-black text-accent`}>{scene}</div>
            {isManual && (
              <span className="bg-accent px-1 text-[0.5rem] font-black uppercase text-black">Manual</span>
            )}
          </div>
          <div className={`${compact ? 'text-[0.5rem]' : 'text-[0.625rem]'} text-text-muted`}>
            {when}{dur != null ? ` · ${Math.round(dur)}s` : ''}{frames ? ` · ${frames}f` : ''}{size ? ` · ${size}` : ''}
          </div>
          {!compact && (
            <div className="truncate text-[0.625rem] text-text-muted">{label}</div>
          )}
        </div>
      </button>
      <div className="flex shrink-0 items-center gap-1">
        {onPlay && (
          <button
            type="button"
            onClick={() => onPlay(hz.id)}
            className="border-2 border-success bg-success/10 p-1 text-success hover:bg-success hover:text-black"
            title="Reproducir en Netlify"
          >
            <Play size={compact ? 10 : 12} fill="currentColor" />
          </button>
        )}
        {onDownload && (
          <button
            type="button"
            onClick={() => onDownload(hz.id, label)}
            className="border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
            title="Descargar"
          >
            <Download size={compact ? 10 : 12} />
          </button>
        )}
        {onTag && (
          <button
            type="button"
            onClick={() => onTag(hz.player_id)}
            className="border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
            title="Taguear"
          >
            <Tag size={compact ? 10 : 12} />
          </button>
        )}
        {onDelete && (
          <button
            type="button"
            onClick={() => onDelete(hz.id, label)}
            className="border-2 border-danger bg-danger/10 p-1 text-danger hover:bg-danger hover:text-white"
            title="Borrar"
          >
            <Trash2 size={compact ? 10 : 12} />
          </button>
        )}
      </div>
    </div>
    {expanded && (
      <div className="border-t-2 border-black/40 px-3 py-2">
        <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-3">
          <HzMeta label="Escena" value={scene} />
          <HzMeta label="Trigger" value={trigger} />
          <HzMeta label="FPS sesión" value={sessionFps != null ? sessionFps.toFixed(1) : '—'} />
          <HzMeta label="Duración" value={dur != null ? `${Math.round(dur)}s` : '—'} />
          <HzMeta label="Frames" value={frames != null ? String(frames) : '—'} />
          <HzMeta label="Tamaño" value={size || '—'} />
          <HzMeta label="Player" value={label} />
          <HzMeta label="Player ID" value={hz.player_id || '—'} />
          <HzMeta label="Grid X,Z" value={grid || '—'} />
          <HzMeta label="Sesión" value={hz.session_id ? String(hz.session_id).slice(0, 12) : '—'} />
          <HzMeta label="Fecha" value={when || '—'} />
        </div>
        {sessionFps == null && (
          <div className="mt-2 text-[0.5rem] italic text-text-muted">
            La serie de FPS por frame está en el blob de la captura; descárgala para reproducirla.
          </div>
        )}
      </div>
    )}
    </div>
  );
};

const HotzoneList = ({
  sessions,
  hotzones,
  onDownloadHotzone,
  onDeleteHotzone,
  onPlayHotzone,
  onTagPlayer,
  compact = false
}: {
  sessions: any[];
  hotzones?: any[];
  onDownloadHotzone?: (hotzoneId: string, label?: string) => void;
  onDeleteHotzone?: (hotzoneId: string, label?: string) => void;
  onPlayHotzone?: (hotzoneId: string) => void;
  onTagPlayer?: (playerId: string) => void;
  compact?: boolean;
}) => {
  const nameByPlayer = useMemo(() => {
    const m: Record<string, string> = {};
    for (const s of sessions) if (s.player_id && s.display_name) m[s.player_id] = s.display_name;
    return m;
  }, [sessions]);

  // Match each hotzone to its owning session (by session_id) so the expanded
  // detail can surface the session's avg FPS as honest FPS context.
  const sessionById = useMemo(() => {
    const m: Record<string, any> = {};
    for (const s of sessions) if (s.session_id) m[s.session_id] = s;
    return m;
  }, [sessions]);

  if (!hotzones || hotzones.length === 0) {
    return <div className="text-xs italic text-text-muted">Sin capturas de hotzone</div>;
  }

  return (
    <div className="flex flex-col gap-1">
      {hotzones.map((hz) => (
        <HotzoneRow
          key={hz.id}
          hz={hz}
          name={nameByPlayer[hz.player_id]}
          session={hz.session_id ? sessionById[hz.session_id] : undefined}
          onPlay={onPlayHotzone}
          onDownload={onDownloadHotzone}
          onDelete={onDeleteHotzone}
          onTag={onTagPlayer}
          compact={compact}
        />
      ))}
    </div>
  );
};

const HistoryOverview = ({ sessions, hotzones, onDownloadHotzone, onDeleteHotzone, onPlayHotzone, onTagPlayer }: { sessions: any[]; hotzones?: any[]; onDownloadHotzone?: (hotzoneId: string, label?: string) => void; onDeleteHotzone?: (hotzoneId: string, label?: string) => void; onPlayHotzone?: (hotzoneId: string) => void; onTagPlayer?: (playerId: string) => void }) => {
  return (
    <div className="flex min-h-full flex-col gap-4">
      {/* Hotzone captures — performance ghosts uploaded by the game, newest first. */}
      <RetroCard title={`Capturas hotzone${hotzones && hotzones.length ? ` (${hotzones.length})` : ''}`}>
        <div className="flex max-h-72 flex-col gap-2 overflow-y-auto">
          <HotzoneList
            sessions={sessions}
            hotzones={hotzones}
            onDownloadHotzone={onDownloadHotzone}
            onDeleteHotzone={onDeleteHotzone}
            onPlayHotzone={onPlayHotzone}
            onTagPlayer={onTagPlayer}
          />
        </div>
      </RetroCard>
    </div>
  );
};

// Compact label/value cell for the collapsible 3D info panel.
const Info = ({ label, value }: { label: string; value: ReactNode }) => (
  <div className="flex flex-col">
    <span className="text-[0.5rem] uppercase text-text-muted">{label}</span>
    <span className="truncate text-[0.625rem]">{value}</span>
  </div>
);

// Historical avg-FPS-per-session line with git commit markers — useful to spot
// which commit moved performance. Standalone so it can live in the Live top
// stripe. Includes a version-metadata overlay (latest commits in range).
const CommitsFpsChart = ({ sessions, commits }: { sessions: any[]; commits: GitCommit[] }) => {
  const fpsSeries = useMemo(() => (
    sessions
      .filter(isDashboardSession)
      .filter((s) => Number(s.start_time) > 0)
      .sort((a, b) => Number(a.start_time) - Number(b.start_time))
      .map((s) => ({
        timestamp: Number(s.start_time),
        label: formatDateTime(Number(s.start_time)),
        avg_fps: Number(s.avg_fps) || 0,
      }))
  ), [sessions]);

  const commitLines = useMemo(() => {
    if (fpsSeries.length === 0) return [];
    const minTs = fpsSeries[0].timestamp;
    const maxTs = fpsSeries[fpsSeries.length - 1].timestamp;
    return commits
      .map((commit) => ({ ...commit, timestamp: Math.floor(new Date(commit.date).getTime() / 1000) }))
      .filter((commit) => commit.timestamp >= minTs && commit.timestamp <= maxTs);
  }, [commits, fpsSeries]);

  const tooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div className="font-black text-accent">{d.label}</div>
        <div>Avg FPS: {d.avg_fps.toFixed(1)}</div>
      </div>
    );
  };

  const renderCommitLabel = (commit: GitCommit) => (props: any) => {
    const x = props.viewBox?.x ?? props.x ?? 0;
    const y = props.viewBox?.y ?? props.y ?? 0;
    const shortSha = commit.sha.slice(0, 7);
    const date = new Date(commit.date).toISOString().slice(0, 10);
    return (
      <g>
        <title>{`${date} · ${commit.message} · ${shortSha}`}</title>
        <text x={x + 4} y={y + 12} fill="#d29922" fontSize={9} transform={`rotate(90 ${x + 4} ${y + 12})`}>
          {shortSha}
        </text>
      </g>
    );
  };

  // Commits in range, newest first, for the version selector.
  const rangeCommits = useMemo(
    () => [...commitLines].sort((a, b) => b.timestamp - a.timestamp),
    [commitLines],
  );

  // Selected version (defaults to the newest). Drives the highlighted marker on
  // the chart and the commit-message panel below the selector.
  const [selectedSha, setSelectedSha] = useState<string | null>(null);
  // Default to the newest commit in range; user moves the selection by clicking
  // the chart (the cursor picks the nearest commit marker).
  const selected = rangeCommits.find((c) => c.sha === selectedSha) || rangeCommits[0] || null;

  // Select the version (commit) nearest to where the user actually clicked.
  // recharts' activeLabel snaps to the nearest *session* point, which makes the
  // cursor hop between sessions instead of versions — so we derive the click
  // time from the pixel X against the visible domain and snap to commits.
  const selectNearestCommitAt = (timeSec: number) => {
    if (commitLines.length === 0) return;
    const nearest = commitLines.reduce((best, c) =>
      Math.abs(c.timestamp - timeSec) < Math.abs(best.timestamp - timeSec) ? c : best
    );
    setSelectedSha(nearest.sha);
  };

  const onChartClick = (e: any) => {
    const rect = wrapElRef.current?.getBoundingClientRect();
    // Prefer the true pixel position (chartX) mapped through the visible domain;
    // fall back to activeLabel if recharts didn't provide coordinates.
    if (rect && typeof e?.chartX === 'number') {
      const [lo, hi] = xDomain ?? [dataMin, dataMax];
      // chartX is relative to the SVG; approximate plot width with the wrapper.
      const frac = Math.min(1, Math.max(0, e.chartX / rect.width));
      selectNearestCommitAt(lo + (hi - lo) * frac);
      return;
    }
    if (typeof e?.activeLabel === 'number') selectNearestCommitAt(e.activeLabel);
  };

  // Step the version selection along the commit timeline (keyboard arrows).
  const stepVersion = (dir: -1 | 1) => {
    if (commitLines.length === 0) return;
    const ordered = [...commitLines].sort((a, b) => a.timestamp - b.timestamp);
    const curIdx = ordered.findIndex((c) => c.sha === (selectedSha ?? ordered[ordered.length - 1].sha));
    const next = ordered[Math.min(ordered.length - 1, Math.max(0, (curIdx < 0 ? ordered.length - 1 : curIdx) + dir))];
    if (next) setSelectedSha(next.sha);
  };

  // Scroll-zoom + drag-pan over the X (time) axis, driven by an explicit domain.
  // null = full range. Bounds come from the data; we never zoom/pan past them.
  const dataMin = fpsSeries.length ? fpsSeries[0].timestamp : 0;
  const dataMax = fpsSeries.length ? fpsSeries[fpsSeries.length - 1].timestamp : 1;
  const [xDomain, setXDomain] = useState<[number, number] | null>(null);
  const wrapElRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<{ startX: number; dom: [number, number]; moved: boolean } | null>(null);

  const clampDomain = (lo: number, hi: number): [number, number] => {
    const fullSpan = dataMax - dataMin || 1;
    let span = Math.min(Math.max(hi - lo, fullSpan / 200), fullSpan); // min 0.5% zoom
    let nlo = lo;
    let nhi = lo + span;
    if (nlo < dataMin) { nlo = dataMin; nhi = nlo + span; }
    if (nhi > dataMax) { nhi = dataMax; nlo = nhi - span; }
    if (nlo < dataMin) nlo = dataMin;
    return [nlo, nhi];
  };

  const onWheel = (e: React.WheelEvent) => {
    if (!fpsSeries.length) return;
    e.preventDefault();
    const rect = wrapElRef.current?.getBoundingClientRect();
    if (!rect) return;
    const [lo, hi] = xDomain ?? [dataMin, dataMax];
    const frac = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    const pivot = lo + (hi - lo) * frac;
    const factor = e.deltaY < 0 ? 0.8 : 1.25; // up = zoom in
    const span = (hi - lo) * factor;
    setXDomain(clampDomain(pivot - span * frac, pivot - span * frac + span));
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (!fpsSeries.length) return;
    dragRef.current = { startX: e.clientX, dom: xDomain ?? [dataMin, dataMax], moved: false };
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const drag = dragRef.current;
    const rect = wrapElRef.current?.getBoundingClientRect();
    if (!drag || !rect) return;
    const [lo, hi] = drag.dom;
    const dxFrac = (e.clientX - drag.startX) / rect.width;
    if (Math.abs(dxFrac) > 0.01) drag.moved = true;
    const shift = -dxFrac * (hi - lo);
    setXDomain(clampDomain(lo + shift, hi + shift));
  };
  const endPointer = () => { dragRef.current = null; };
  // Suppress the select-on-click that fires at the end of a pan drag.
  const onChartClickGuarded = (e: any) => {
    if (dragRef.current?.moved) return;
    onChartClick(e);
  };
  const isZoomed = xDomain !== null && (xDomain[0] > dataMin || xDomain[1] < dataMax);

  if (fpsSeries.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-xs italic text-text-muted">
        No session history yet
      </div>
    );
  }

  return (
    <div
      ref={wrapElRef}
      className="relative h-full w-full touch-none select-none"
      onWheel={onWheel}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endPointer}
      onPointerLeave={endPointer}
      style={{ cursor: dragRef.current ? 'grabbing' : 'grab' }}
    >
      <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
        <LineChart data={fpsSeries} margin={{ top: 4, right: 8, bottom: 0, left: -8 }} onClick={onChartClickGuarded}>
          <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
          <XAxis dataKey="timestamp" stroke="#666" fontSize={10} type="number" allowDataOverflow domain={xDomain ?? ['dataMin', 'dataMax']} tickFormatter={(v) => new Date(Number(v) * 1000).toISOString().slice(5, 10)} />
          <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} width={28} />
          <Tooltip content={tooltip} />
          {commitLines.map((commit) => {
            const isSel = selected?.sha === commit.sha;
            return (
              <ReferenceLine
                key={commit.sha}
                x={commit.timestamp}
                stroke={isSel ? '#f85149' : '#d29922'}
                strokeWidth={isSel ? 2 : 1}
                strokeDasharray={isSel ? undefined : '3 3'}
                label={renderCommitLabel(commit)}
              />
            );
          })}
          <Line type="monotone" dataKey="avg_fps" stroke="#7fd1ff" dot={{ r: 3 }} strokeWidth={2} isAnimationActive={false} />
        </LineChart>
      </ResponsiveContainer>

      {/* Zoom hint + reset, shown once the user has zoomed/panned in. */}
      {isZoomed && (
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); setXDomain(null); }}
          onPointerDown={(e) => e.stopPropagation()}
          className="absolute right-2 top-2 z-10 border-2 border-black bg-bg-card/90 px-2 py-0.5 text-[0.5625rem] font-black uppercase text-text-muted shadow-[2px_2px_0px_0px_black] hover:bg-accent hover:text-black"
          title="Restablecer zoom"
        >
          Reset zoom
        </button>
      )}

      {/* Selected version metadata — moves with the chart cursor (click to pick
          the nearest commit). */}
      {selected && (
        <div className="absolute left-2 top-2 max-w-[78%] border-2 border-black bg-bg-card/90 px-2 py-1.5 text-[0.5625rem] font-mono shadow-[2px_2px_0px_0px_black]">
          <div className="mb-0.5 flex items-center gap-1.5 font-black uppercase tracking-widest text-[#d29922]">
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); stepVersion(-1); }}
              onPointerDown={(e) => e.stopPropagation()}
              className="border border-black bg-bg-primary px-1 leading-none hover:bg-accent hover:text-black"
              title="Versión anterior"
            >‹</button>
            <span>Versión · <span className="text-[#f85149]">{selected.sha.slice(0, 7)}</span> · {new Date(selected.date).toISOString().slice(0, 10)}</span>
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); stepVersion(1); }}
              onPointerDown={(e) => e.stopPropagation()}
              className="border border-black bg-bg-primary px-1 leading-none hover:bg-accent hover:text-black"
              title="Versión siguiente"
            >›</button>
          </div>
          <div className="whitespace-pre-wrap break-words text-text-primary">{selected.message.split('\n')[0]}</div>
          <div className="mt-1 text-text-muted/70">Click o ‹ › para elegir versión · scroll = zoom · arrastrar = pan</div>
        </div>
      )}
    </div>
  );
};

type GhostStats = {
  unique_players_total?: number;
  players_last_day?: number;
  players_last_week?: number;
  players_last_month?: number;
  // Previous equally-sized window, for trend/delta display.
  players_prev_day?: number;
  players_prev_week?: number;
  players_prev_month?: number;
  // Daily unique players over the last 30d (sparkline).
  players_daily?: number[];
  max_concurrent_players?: number;
  total_sessions?: number;
};

// One player-activity card: count + delta vs the previous equal window + a
// sparkline of the daily series. Delta and sparkline are optional so the card
// degrades gracefully against older backends that don't send them.
const PlayerStatCard = ({
  label, value, prev, series,
}: {
  label: string;
  value?: number;
  prev?: number;
  series?: number[];
}) => {
  const num = (v: any): v is number => typeof v === 'number' && Number.isFinite(v);
  const hasValue = num(value);
  const hasDelta = hasValue && num(prev);
  // Percent change vs previous window; when prev is 0 we show the raw count as a
  // "new" gain rather than a divide-by-zero.
  const deltaPct = hasDelta && prev! > 0 ? ((value! - prev!) / prev!) * 100 : null;
  const deltaUp = hasDelta ? value! >= prev! : false;
  const sparkData = (series || []).map((n, i) => ({ i, n }));

  return (
    <div className="flex flex-col gap-1 border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-xl font-black tracking-tighter sm:text-2xl">
          {hasValue ? value : '—'}
        </span>
        {hasDelta && (
          <span className={`text-[0.625rem] font-black ${deltaUp ? 'text-success' : 'text-danger'}`}>
            {deltaUp ? '▲' : '▼'}
            {deltaPct !== null ? `${Math.abs(deltaPct).toFixed(0)}%` : `${value! - prev!}`}
          </span>
        )}
      </div>
      <div className="text-[0.5625rem] font-black uppercase text-text-muted">{label}</div>
      {sparkData.length > 1 && (
        <div className="mt-1 h-8">
          <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
            <LineChart data={sparkData}>
              <Line type="monotone" dataKey="n" stroke="#7fd1ff" dot={false} strokeWidth={1.5} isAnimationActive={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
};

const HomeStats = ({ sessions, serverStats }: { sessions: any[]; serverStats?: GhostStats }) => {
  const cleanSessions = useMemo(() => (
    sessions.filter(isDashboardSession)
  ), [sessions]);

  const stats = useMemo(() => {
    const fpsValues = cleanSessions.map((s) => Number(s.avg_fps)).filter((n) => Number.isFinite(n));
    const memValues = cleanSessions.map((s) => Number(s.avg_mem)).filter((n) => Number.isFinite(n) && n > 0);
    const totalDuration = cleanSessions.reduce((sum, s) => sum + (Number(s.duration) || 0), 0);
    const avgFps = fpsValues.reduce((sum, fps) => sum + fps, 0) / (fpsValues.length || 1);
    const avgMem = memValues.length ? memValues.reduce((sum, m) => sum + m, 0) / memValues.length : 0;
    const lowPct = cleanSessions.length
      ? cleanSessions.filter((s) => (Number(s.avg_fps) || 0) < 30).length * 100 / cleanSessions.length
      : 0;
    const lastSession = cleanSessions.reduce((latest, s) => {
      const ts = Number(s.start_time) || 0;
      return ts > latest ? ts : latest;
    }, 0);
    return { avgFps, avgMem, totalDuration, lowPct, lastSession };
  }, [cleanSessions]);

  // Performance/usage headline stats (derived from the filtered session list)
  // share one compact grid. Player-count stats from the server now live in their
  // own "Players" section below (see PlayerStatCard).
  const num = (v: any): v is number => typeof v === 'number' && Number.isFinite(v);
  const statCells: Array<{ label: string; value: string; color?: string }> = [
    { label: 'Avg FPS', value: stats.avgFps.toFixed(1), color: fpsColor(stats.avgFps) },
    { label: 'Avg Memory', value: stats.avgMem > 0 ? `${stats.avgMem.toFixed(0)} MB` : '—' },
    { label: 'Sessions', value: cleanSessions.length.toString() },
    { label: 'Play Time', value: formatPlayTime(stats.totalDuration) },
    { label: '% Low FPS', value: `${stats.lowPct.toFixed(1)}%`, color: fpsColor(100 - stats.lowPct) },
    { label: 'Scenes', value: new Set(cleanSessions.flatMap(sessionScenes)).size.toString() },
  ];

  // Show the Players section only when the server reported player metrics (the
  // endpoint may return {} on an empty DB).
  const hasPlayerStats = num(serverStats?.unique_players_total)
    || num(serverStats?.players_last_day)
    || num(serverStats?.players_last_week)
    || num(serverStats?.players_last_month);

  return (
    <div className="flex flex-col gap-4 p-4 sm:p-6">
      {!navigator.onLine && (
        <div className="flex items-center gap-2 border-2 border-black bg-danger px-4 py-2 font-black uppercase text-black shadow-[4px_4px_0px_0px_black]">
          <WifiOff size={20} />
          <span>Modo Offline — Mostrando datos de la última sesión</span>
        </div>
      )}
      {/* Performance / usage headline stats share one compact card. */}
      <RetroCard>
        <div className="grid grid-cols-3 gap-4 sm:grid-cols-6">
          {statCells.map((card) => (
            <div key={card.label} className="min-w-0">
              <div className="truncate text-lg font-black tracking-tighter sm:text-2xl" style={card.color ? { color: card.color } : undefined}>
                {card.value}
              </div>
              <div className="mt-1 text-[0.5625rem] font-black uppercase text-text-muted">{card.label}</div>
            </div>
          ))}
        </div>
      </RetroCard>

      {/* Players section: time-windowed unique-player cards with trend + spark. */}
      {hasPlayerStats && (
        <div className="flex flex-col gap-2">
          <div className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Players</div>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            <PlayerStatCard
              label="24h"
              value={serverStats?.players_last_day}
              prev={serverStats?.players_prev_day}
              series={serverStats?.players_daily?.slice(-2)}
            />
            <PlayerStatCard
              label="7 días"
              value={serverStats?.players_last_week}
              prev={serverStats?.players_prev_week}
              series={serverStats?.players_daily?.slice(-7)}
            />
            <PlayerStatCard
              label="30 días"
              value={serverStats?.players_last_month}
              prev={serverStats?.players_prev_month}
              series={serverStats?.players_daily}
            />
            <PlayerStatCard label="Total únicos" value={serverStats?.unique_players_total} />
            <PlayerStatCard label="Max concurrentes" value={serverStats?.max_concurrent_players} />
          </div>
        </div>
      )}
    </div>
  );
};

const SceneIndex = ({
  sessions,
  scenes,
  selectedScene,
  onSelectScene,
}: {
  sessions: any[];
  scenes: string[];
  selectedScene: string;
  onSelectScene: (scene: string) => void;
}) => {
  const sceneStats = useMemo(() => {
    const cleanSessions = sessions.filter(isDashboardSession);
    return scenes.map((scene) => {
      const sceneSessions = cleanSessions
        .filter((session) => sessionScenes(session).length === 0 || sessionScenes(session).includes(scene))
        .sort((a, b) => (Number(a.start_time) || 0) - (Number(b.start_time) || 0));
      const fpsValues = sceneSessions.map((session) => Number(session.avg_fps)).filter(Number.isFinite);
      const avgFps = fpsValues.reduce((sum, fps) => sum + fps, 0) / (fpsValues.length || 1);
      const lowPct = sceneSessions.length
        ? sceneSessions.filter((session) => (Number(session.avg_fps) || 0) < 30).length * 100 / sceneSessions.length
        : 0;
      return {
        scene,
        sessions: sceneSessions.length,
        avgFps,
        lowPct,
        trend: sceneSessions.map((session) => ({
          timestamp: Number(session.start_time) || 0,
          label: formatDateTime(Number(session.start_time) || 0),
          avg_fps: Number(session.avg_fps) || 0,
        })),
      };
    })
      .filter((stat) => stat.sessions > 0)
      // Most-played scenes first (tie-break alphabetically for stable ordering).
      .sort((a, b) => b.sessions - a.sessions || a.scene.localeCompare(b.scene));
  }, [sessions, scenes]);

  const sceneTrendTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.5625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div className="font-black text-accent">{d.label}</div>
        <div className="text-text-muted">Range: sessions over time</div>
        <div>Avg FPS: {d.avg_fps.toFixed(1)}</div>
      </div>
    );
  };

  return (
    <div className="grid max-h-full grid-cols-1 gap-2 overflow-y-auto pr-1 sm:grid-cols-2 xl:grid-cols-1">
      {sceneStats.map((stat) => {
        const active = selectedScene === stat.scene;
        return (
          <button
            key={stat.scene}
            type="button"
            onClick={() => onSelectScene(stat.scene)}
            className={`border-2 border-black bg-bg-card p-3 text-left shadow-[2px_2px_0px_0px_black] transition-colors hover:bg-accent/5 ${active ? 'outline outline-2 outline-accent' : ''}`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="truncate text-xs font-black text-accent">{stat.scene}</div>
                <div className="mt-1 text-[0.625rem] font-black uppercase text-text-muted">
                  {stat.sessions} sessions · {stat.lowPct.toFixed(1)}% low
                </div>
              </div>
              <div className="text-right">
                <div className="text-lg font-black" style={{ color: fpsColor(stat.avgFps) }}>
                  {stat.avgFps.toFixed(1)}
                </div>
                <div className="text-[0.5rem] font-black uppercase text-text-muted">avg fps</div>
              </div>
            </div>
            <div className="mt-3 h-12">
              <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
                <LineChart data={stat.trend}>
                  <Tooltip content={sceneTrendTooltip} />
                  <Line type="monotone" dataKey="avg_fps" stroke="#7fd1ff" dot={false} strokeWidth={2} isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </button>
        );
      })}
    </div>
  );
};

// Shown in the Live view while we wait for the first heartbeat: instead of a
// dead "no player" line, rotate through aggregate stats so the screen feels
// alive during the (sometimes slow) wait for live telemetry.
const LiveWaitTicker = ({ items }: { items: { label: string; value: string }[] }) => {
  const [idx, setIdx] = useState(0);
  useEffect(() => {
    if (items.length <= 1) return;
    const id = setInterval(() => setIdx((i) => (i + 1) % items.length), 2500);
    return () => clearInterval(id);
  }, [items.length]);
  const safe = items.length ? items[idx % items.length] : null;
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 p-6 text-center">
      <div className="flex items-center gap-2 text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
        <span className="h-2 w-2 animate-pulse rounded-full bg-warning" />
        Esperando telemetría en vivo…
      </div>
      {safe && (
        <div key={idx} className="animate-in fade-in slide-in-from-bottom-2 duration-300">
          <div className="text-4xl font-black tracking-tighter text-accent">{safe.value}</div>
          <div className="mt-1 text-[0.625rem] font-black uppercase tracking-widest text-text-muted">{safe.label}</div>
        </div>
      )}
      <div className="flex gap-1">
        {items.map((_, i) => (
          <span key={i} className={`h-1 w-4 ${i === idx % items.length ? 'bg-accent' : 'bg-text-muted/30'}`} />
        ))}
      </div>
    </div>
  );
};

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, isConnected, alerts, history, health, lastMessage } = useTelemetry();
  const { layout, updateLayout } = useLayoutPersistence();
  
  const activeTab = layout.activeTab as Tab;
  const setActiveTab = (t: Tab) => updateLayout({ activeTab: t });

  // Desktop docked filters sidebar collapsed state + History min-duration
  // filter, both persisted across reloads.
  const filtersCollapsed = layout.filtersCollapsed;
  const setFiltersCollapsed = (v: boolean) => updateLayout({ filtersCollapsed: v });
  const minDuration = layout.historyMinDuration;
  const setMinDuration = (seconds: number) => updateLayout({ historyMinDuration: seconds });

  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);

  // Notification deep-link: focus on a specific player from URL params
  const [focusPlayerId, setFocusPlayerId] = useState<string | null>(null);
  const [showTagEditor, setShowTagEditor] = useState(false);
  const [showSettings, setShowSettings] = useState(false);

  // Read query params on mount for deep-link
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const pid = params.get('player');
    if (pid) setFocusPlayerId(pid);
  }, []);

  // Live tab view toggle: dashboard, 2D birdseye map, or 3D perspective.
  const [liveView, setLiveView] = useState<'dashboard' | 'birdseye' | '3d'>('dashboard');
  // CSS overlay fullscreen for the 3D canvas (NOT the browser Fullscreen API,
  // which is unreliable on mobile).
  const [fs3d, setFs3d] = useState(false);
  const [fsBirdseye, setFsBirdseye] = useState(false);
  // Player list bottom sheet (opened from the header counter).
  const [showPlayerSheet, setShowPlayerSheet] = useState(false);
  // Live FPS/memory charts overlay over the 3D view.
  const [showLiveCharts, setShowLiveCharts] = useState(true);
  // Selected ghost in birdseye -> floating detail card with live charts.
  const [birdseyeDetailId, setBirdseyeDetailId] = useState<string | null>(null);
  // Filters side drawer (platform + scene).
  const [showFilters, setShowFilters] = useState(false);
  // Top-stripe inner tab on the Dashboard view (live combined chart vs sessions).
  const [dashStripeTab, setDashStripeTab] = useState<'live' | 'sessions' | 'versions'>('live');
  const viewport3DPreloaded = useRef(false);

  // Playback loading flag (history -> playback fetch).
  const [playbackLoading, setPlaybackLoading] = useState(false);

  // Play a hotzone. On Android, try to hand the signed capture URL to the
  // installed native build via the odisea://replay deep link; if that app
  // isn't installed the deep link silently no-ops, so we fall back to the
  // web (Netlify) shell after a short grace period. Everywhere else we go
  // straight to the web shell.
  const handlePlayHotzone = useCallback(async (hotzoneId: string) => {
    try {
      const { url } = await getHotzoneDownloadLink(hotzoneId);
      const webUrl = `https://odisea-game.netlify.app/?runbin=${encodeURIComponent(url)}`;
      const isAndroid = /android/i.test(navigator.userAgent);
      if (isAndroid) {
        const deepLink = `odisea://replay?url=${encodeURIComponent(url)}`;
        // If the native app handles the deep link, the browser tab is
        // backgrounded and our fallback timer is suspended; if nothing handles
        // it, the timer fires and we open the web shell instead.
        let launched = false;
        const onHide = () => { launched = true; };
        document.addEventListener('visibilitychange', onHide, { once: true });
        window.location.href = deepLink;
        setTimeout(() => {
          document.removeEventListener('visibilitychange', onHide);
          if (!launched && !document.hidden) {
            window.open(webUrl, '_blank', 'noopener,noreferrer');
          }
        }, 1500);
        return;
      }
      window.open(webUrl, '_blank', 'noopener,noreferrer');
    } catch {
      notify.error('No se pudo generar el enlace de reproducción');
    }
  }, []);

  // Heatmap State
  const [heatmapRes, setHeatmapRes] = useState(5);
  // Heatmap sub-tab, surfaced as a secondaryNav (like Live). 'scenes'/'map'
  // mirror the old mobile pane toggle; 'stats' is the dedicated summary view
  // (FD-223) that shows the heatmapSummary cards instead of a top-level tab.
  const [heatmapView, setHeatmapView] = useState<'scenes' | 'map' | 'stats'>('scenes');
  // History tab mobile pane toggle (session list vs playback), mirrors heatmap.
  const [historyMobileView, setHistoryMobileView] = useState<'list' | 'hotzones' | 'player'>('list');

  // Available scenes (fetched from backend, not hardcoded)
  const [scenes, setScenes] = useState<string[]>([]);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState<any[]>([]);
  const [selectedSession, setSelectedSession] = useState<any>(null);
  const [playbackData, setPlaybackData] = useState<any[]>([]);
  const [commits, setCommits] = useState<GitCommit[]>([]);
  const [serverStats, setServerStats] = useState<GhostStats>({});
  const [hotzones, setHotzones] = useState<any[]>([]);
  const [geoPlayers, setGeoPlayers] = useState<any[]>([]);
  const loadGeoPlayers = useCallback(() => {
    getGeoPlayers()
      .then(setGeoPlayers)
      .catch(() => setGeoPlayers([]));
  }, []);
  const [selectedPlatforms, setSelectedPlatforms] = useState<Set<string>>(
    () => new Set(KNOWN_PLATFORMS.filter((platform) => platform !== 'server'))
  );
  const [selectedSceneFilter, setSelectedSceneFilter] = useState('all');
  const [selectedCountry, setSelectedCountry] = useState('all');

  // Restore the default filters: all scenes, every platform except the headless
  // server, all countries.
  const resetFilters = () => {
    setSelectedPlatforms(new Set(KNOWN_PLATFORMS.filter((platform) => platform !== 'server')));
    setSelectedSceneFilter('all');
    setSelectedCountry('all');
    setMinDuration(DEFAULT_HISTORY_MIN_DURATION);
  };
  const [lastLivePlayerCount, setLastLivePlayerCount] = useState(0);
  const alertToastTimes = useRef<Map<string, number>>(new Map());

  // Live State
  const [liveGhosts, setLiveGhosts] = useState<any[]>([]);


  useEffect(() => {
    if (alerts.length > 0) {
        const latest = alerts[0];
        toast(latest.message, {
            icon: latest.type === 'disconnect' ? '❌' : '⚠️',
            style: {
                borderRadius: '0px',
                background: '#13161c',
                color: '#d7dbe0',
                border: '4px solid #000',
                fontSize: '12px',
                fontFamily: 'monospace',
                boxShadow: '4px 4px 0px 0px #000'
            },
        });
    }
  }, [alerts]);

  useEffect(() => {
    if (lastMessage?.type === 'alert') {
      const playerId = lastMessage.playerId || lastMessage.player_id || 'unknown';
      const alertType = lastMessage.alertType || lastMessage.alert_type || 'alert';

      // Optimistic Hotzone insertion
      if (alertType === 'hotzone' && lastMessage.hotzoneId) {
        const optimisticHz = {
          id: lastMessage.hotzoneId,
          player_id: playerId,
          session_id: lastMessage.sessionId || lastMessage.session_id,
          scene: lastMessage.scene,
          trigger_type: lastMessage.trigger || 'auto',
          timestamp: lastMessage.timestamp || (Date.now() / 1000),
          display_name: lastMessage.display_name,
          capture_duration: lastMessage.capture_duration,
          frame_count: lastMessage.frame_count,
          is_optimistic: true // Marker for reconciliation
        };
        setHotzones((prev) => [optimisticHz, ...prev.filter(h => h.id !== lastMessage.hotzoneId)]);

        // Reconciliation fetch
        setTimeout(() => {
          getHotzones()
            .then((d) => setHotzones(Array.isArray(d) ? d : []))
            .catch(() => {});
        }, 3000);
      }

      const alertPlatform = getPlatform(lastMessage);
      if (alertPlatform === 'server') return;
      const key = `${playerId}|${alertType}`;
      const now = Date.now();
      const lastToast = alertToastTimes.current.get(key) || 0;
      if (now - lastToast < 60000) return;
      alertToastTimes.current.set(key, now);

      // Enrich the alert with whatever runtime context we have: prefer the
      // alert payload, fall back to the player's current heartbeat.
      const liveHb: any = heartbeats[playerId];
      const playerLabel = lastMessage.display_name || lastMessage.playerName || liveHb?.display_name || playerId;
      const ctxScene = lastMessage.scene ?? lastMessage.player?.scene ?? liveHb?.player?.scene;
      const ctxPlatform = alertPlatform ?? getPlatform(liveHb);
      const ctxFps = lastMessage.fps ?? lastMessage.player?.fps ?? liveHb?.player?.fps;
      const ctxMem = lastMessage.memory_mb ?? lastMessage.player?.memory_mb ?? liveHb?.player?.memory_mb;
      const ctxParts = [
        ctxScene ? `scene ${ctxScene}` : null,
        ctxPlatform ? ctxPlatform : null,
        typeof ctxFps === 'number' ? `${Math.round(ctxFps)} fps` : null,
        typeof ctxMem === 'number' && ctxMem > 0 ? `${ctxMem.toFixed(0)} MB` : null,
        lastMessage.capture_duration ? `${Math.round(lastMessage.capture_duration)}s` : null,
        lastMessage.frame_count ? `${lastMessage.frame_count} frames` : null,
      ].filter(Boolean);

      toast.custom((t) => (
        <div className={`${t.visible ? 'opacity-100' : 'opacity-0'} border-4 border-accent bg-bg-card p-3 font-mono text-xs text-text-primary shadow-[4px_4px_0px_0px_black] transition-opacity max-w-sm`}>
          <div className="flex items-start gap-3">
            <span className="text-base">🔥</span>
            <div className="min-w-0 flex-1">
              <div className="font-black uppercase text-accent">
                {playerLabel}{alertType && alertType !== 'alert' ? ` · ${alertType}` : ''}
              </div>
              <div className="mt-1 text-text-muted">{lastMessage.message}</div>
              {ctxParts.length > 0 && (
                <div className="mt-1 text-[0.625rem] uppercase tracking-wide text-text-muted/80">
                  {ctxParts.join(' · ')}
                </div>
              )}
              <div className="mt-3 flex flex-wrap gap-2">
                {alertType === 'hotzone' && lastMessage.hotzoneId && (
                  <>
                    <button
                      type="button"
                      onClick={() => { handleDownloadHotzone(lastMessage.hotzoneId, playerLabel); toast.dismiss(t.id); }}
                      className="border-2 border-black bg-accent px-2 py-1 text-[0.625rem] font-black uppercase text-black"
                    >
                      Descargar
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setFocusPlayerId(playerId);
                        setShowTagEditor(true);
                        toast.dismiss(t.id);
                      }}
                      className="border-2 border-black bg-accent px-2 py-1 text-[0.625rem] font-black uppercase text-black"
                    >
                      Taguear
                    </button>
                  </>
                )}
                {playerId !== 'unknown' && heartbeats[playerId] && (
                  <button
                    type="button"
                    onClick={() => {
                      setSelectedPlayerId(playerId);
                      setActiveTab('live');
                      setLiveView('3d');
                      setFollowPlayer(true);
                      toast.dismiss(t.id);
                    }}
                    className="border-2 border-black bg-accent px-2 py-1 text-[0.625rem] font-black uppercase text-black"
                  >
                    Ver live
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => toast.dismiss(t.id)}
                  className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-black uppercase"
                >
                  Dismiss
                </button>
              </div>
            </div>
          </div>
        </div>
      ), { duration: 8000 });
    }
  }, [lastMessage, setActiveTab, heartbeats]);

  useEffect(() => {
    const active = Object.entries(heartbeats).filter(([, hb]: [string, any]) => {
      const platform = getPlatform(hb);
      const scene = hb?.player?.scene ?? hb?.scene;
      const platformMatch = !platform || selectedPlatforms.has(platform);
      const sceneMatch = selectedSceneFilter === 'all' || !scene || scene === selectedSceneFilter;
      return platformMatch && sceneMatch;
    }).map(([pid, hb]: [string, any]) => {
      const p = hb.player || {};
      const pos = p.position || [0,0,0];
      return {
        player_id: pid,
        display_name: hb.display_name,
        color: hb.color,
        session_id: hb.session_id,
        scene: p.scene,
        platform: getPlatform(hb),
        pos_x: pos[0],
        pos_y: pos[1],
        pos_z: pos[2],
        fps: p.fps,
        memory_mb: p.memory_mb,
        mode: p.mode,
        last_seen: hb.timestamp,
        intake_mode: hb.intake_mode,
        game_version: hb.game_version,
        git_commit: hb.git_commit,
        build_channel: hb.build_channel,
        official_build: hb.official_build,
      };
    });
    setLiveGhosts(active);
  }, [heartbeats, selectedPlatforms, selectedSceneFilter]);

  useEffect(() => {
    const interval = setInterval(() => {
      const cutoff = Date.now() - 5 * 60 * 1000;
      alertToastTimes.current.forEach((timestamp, key) => {
        if (timestamp < cutoff) alertToastTimes.current.delete(key);
      });
    }, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    getScenes()
      .then((d) => setScenes(Array.isArray(d) ? d : []))
      .catch(() => setScenes([]));
  }, []);

  // Keep the historical list live: refetch periodically so sessions that have
  // been persisted to SQLite appear without a manual reload. (Sessions still in
  // flight are injected from heartbeats in liveHistoricalSessions below.)
  useEffect(() => {
    const loadSessions = () => {
      getHistoricalSessions()
        .then((d) => setHistoricalSessions(Array.isArray(d) ? d : []))
        .catch(() => {});
      getGhostStats()
        .then((d) => setServerStats(d && typeof d === 'object' ? d : {}))
        .catch(() => {});
      getHotzones()
        .then((d) => setHotzones(Array.isArray(d) ? d : []))
        .catch(() => {});
    };
    loadSessions();
    const interval = setInterval(loadSessions, 60000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    fetch('https://api.github.com/repos/icarito/Odisea/commits?per_page=40')
      .then((response) => response.ok ? response.json() : [])
      .then((data) => {
        if (!Array.isArray(data)) {
          setCommits([]);
          return;
        }
        setCommits(data.map((item: any) => ({
          sha: item.sha || '',
          date: item.commit?.committer?.date || item.commit?.author?.date || '',
          message: item.commit?.message || '',
        })).filter((item: GitCommit) => item.sha && item.date));
      })
      .catch(() => setCommits([]));
  }, []);

  // Announce a freshly published nightly: watch latest_published.git_commit from
  // /health and toast once when it changes, with the commit message looked up in
  // the GitHub commit list. The first observed value is recorded silently (no
  // toast on initial load).
  const lastPublishedCommit = useRef<string | null>(null);
  useEffect(() => {
    const published = health?.latest_published;
    const sha: string | undefined = published?.git_commit;
    if (!sha) return;
    if (lastPublishedCommit.current === null) {
      lastPublishedCommit.current = sha; // seed silently on first load
      return;
    }
    if (lastPublishedCommit.current === sha) return;
    lastPublishedCommit.current = sha;
    const channel = String(published?.build_channel || 'build');
    const msg = commits.find((c) => c.sha.startsWith(sha) || sha.startsWith(c.sha))?.message?.split('\n')[0];
    notify.success(`Nuevo ${channel} publicado · ${sha.slice(0, 7)}`, {
      description: msg || undefined,
      important: true,
      data: { tag: `published-${sha.slice(0, 7)}` },
    });
  }, [health?.latest_published?.git_commit, commits]);

  // Detect a new dashboard deploy from /health.dashboard_version. Ask the SW to
  // update, but only activate/reload after the new SW has installed its precache.
  // On slow links this avoids reloading onto an incomplete app shell.
  const loadedDashboardVersion = useRef<string | null>(null);
  const dashboardReloadScheduled = useRef(false);
  useEffect(() => {
    const ver: string | undefined = health?.dashboard_version;
    if (!ver) return;
    if (loadedDashboardVersion.current === null) {
      loadedDashboardVersion.current = ver; // seed with the version we booted on
      return;
    }
    if (loadedDashboardVersion.current === ver) return;
    if (dashboardReloadScheduled.current) return;
    dashboardReloadScheduled.current = true;

    updateDashboardWhenCached().catch((err) => {
      console.warn('Dashboard update check failed', err);
      dashboardReloadScheduled.current = false;
    });
  }, [health?.dashboard_version]);

  // Post-reload announcement: main.tsx sets this sessionStorage flag right before
  // it reloads onto a new SW. We fire the toast from here (inside React) so the
  // <Toaster> is guaranteed mounted — emitting it from main.tsx before mount drops
  // it. Runs once on mount.
  useEffect(() => {
    try {
      if (sessionStorage.getItem(DASHBOARD_UPDATED_FLAG)) {
        sessionStorage.removeItem(DASHBOARD_UPDATED_FLAG);
        notify.success('Dashboard actualizado a la última versión', {
          important: true,
          data: { tag: 'dashboard-update' },
        });
      }
    } catch { /* ignore */ }
  }, []);

  // Normalizes a heartbeat to the flat shape the playback charts use.
  // /api/ghosts returns flat SQLite rows (hb.fps, hb.pos_x, ...), while the
  // runtime/JSONL format nests them under hb.player. Support both.
  const normalizeHeartbeat = (hb: any) => {
    const p = hb.player || {};
    const pos = p.position;
    return {
      timestamp: hb.timestamp ?? 0,
      fps: hb.fps ?? p.fps ?? 0,
      memory_mb: hb.memory_mb ?? p.memory_mb ?? 0,
      pos_x: hb.pos_x ?? pos?.[0] ?? 0,
      pos_y: hb.pos_y ?? hb.player?.position?.[1] ?? pos?.[1] ?? 0,
      pos_z: hb.pos_z ?? pos?.[2] ?? 0,
      scene: hb.scene ?? p.scene ?? "?",
      platform: hb.platform ?? p.platform ?? "?",
      engine_version: hb.engine_version ?? hb.godot_version ?? p.engine_version ?? "?",
    };
  };

  // session_id -> its hotzone ghosts (most recent first), so the History table
  // can show a download affordance on sessions that produced one.
  const hotzonesBySession = useMemo(() => {
    const map: Record<string, any[]> = {};
    for (const hz of hotzones) {
      if (!hz.session_id) continue;
      (map[hz.session_id] ||= []).push(hz);
    }
    for (const k in map) map[k].sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
    return map;
  }, [hotzones]);

  // Download a hotzone ghost binary, surfacing success/failure via notify.
  const handleDownloadHotzone = useCallback(async (hotzoneId: string, label?: string) => {
    try {
      await downloadHotzone(hotzoneId, label);
      notify.success('Hotzone descargada');
    } catch {
      notify.error('No se pudo descargar la hotzone');
    }
  }, []);

  // Delete a hotzone ghost (server + local state), confirming first.
  const handleDeleteHotzone = useCallback(async (hotzoneId: string, label?: string) => {
    if (!window.confirm(`¿Borrar la hotzone${label ? ` de ${label}` : ''}? No se puede deshacer.`)) return;
    try {
      await deleteHotzone(hotzoneId);
      setHotzones((prev) => prev.filter((hz) => hz.id !== hotzoneId));
      notify.success('Hotzone borrada');
    } catch {
      notify.error('No se pudo borrar la hotzone');
    }
  }, []);

  const handleSelectHistorySession = async (session: any) => {
    setSelectedSession(session);
    setHistoryMobileView('player');
    setPlaybackData([]);
    setPlaybackLoading(true);
    try {
      const data = await getGhostData(session.player_id, session.session_id);
      let rows: any[] = [];
      if (Array.isArray(data)) {
        rows = data;
      } else if (typeof data === 'string') {
        rows = data.split('\n').filter(l => l.trim()).map(l => JSON.parse(l));
      }
      setPlaybackData(rows.map(normalizeHeartbeat));
    } catch (e) {
      notify.error("Failed to load session data");
      setPlaybackData([]);
    } finally {
      setPlaybackLoading(false);
    }
  };

  const [followPlayer, setFollowPlayer] = useState(true);

  // Platforms ordered by popularity (session count, desc). Counts across the
  // current session set; platforms with no sessions keep their known order at the
  // tail so they're still selectable.
  // Session counts per platform (history + live), and the platform list ordered
  // by that popularity. The counts also feed the filter UI badges.
  const platformCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    const tally = (rows: any[]) => {
      for (const r of rows) {
        const p = getPlatform(r);
        if (p) counts[p] = (counts[p] || 0) + 1;
      }
    };
    tally(historicalSessions);
    tally(Object.values(heartbeats));
    return counts;
  }, [historicalSessions, heartbeats]);

  const availablePlatforms = useMemo(() => (
    [...KNOWN_PLATFORMS].sort((a, b) => {
      const diff = (platformCounts[b] || 0) - (platformCounts[a] || 0);
      if (diff !== 0) return diff;
      return KNOWN_PLATFORMS.indexOf(a) - KNOWN_PLATFORMS.indexOf(b);
    })
  ), [platformCounts]);

  const availableSceneFilters = useMemo(() => {
    const found = new Set<string>();
    scenes.forEach((scene) => {
      if (isUsefulSceneName(scene)) found.add(scene.trim());
    });
    Object.values(heartbeats).forEach((hb: any) => {
      const scene = hb?.player?.scene ?? hb?.scene;
      if (isUsefulSceneName(scene)) found.add(scene.trim());
    });
    historicalSessions.forEach((session) => {
      sessionScenes(session).forEach((scene) => {
        if (isUsefulSceneName(scene)) found.add(scene.trim());
      });
    });
    return Array.from(found).sort();
  }, [scenes, heartbeats, historicalSessions]);

  const heatmapTargetScene = selectedSceneFilter === 'all'
    ? ''
    : selectedSceneFilter;

  const platformAllowed = (item: any) => {
    const platform = getPlatform(item);
    return !platform || selectedPlatforms.has(platform);
  };

  const sceneAllowed = (item: any) => {
    if (selectedSceneFilter === 'all') return true;
    const itemScenes = item?.player?.scene || item?.scene
      ? [item?.player?.scene ?? item?.scene]
      : sessionScenes(item);
    return itemScenes.length === 0 || itemScenes.includes(selectedSceneFilter);
  };

  const filteredHeartbeats = useMemo(() => (
    Object.fromEntries(Object.entries(heartbeats).filter(([, hb]) => platformAllowed(hb) && sceneAllowed(hb)))
  ), [heartbeats, selectedPlatforms, selectedSceneFilter]);

  // Synthetic session rows for sessions currently in flight (from live
  // heartbeats), so a new session shows in History immediately — before the
  // periodic SQLite import persists it. Shaped like the /api/ghosts/sessions
  // rows the table expects.
  // Real session start times (MIN timestamp per session) from the persisted
  // history, so a live session's uptime counts from when it actually began —
  // the heartbeat itself carries no session_start, only the latest timestamp.
  const sessionStartById = useMemo(() => {
    const map: Record<string, number> = {};
    for (const s of historicalSessions) {
      const start = Number(s.start_time);
      if (s.session_id && Number.isFinite(start) && start > 0) {
        map[s.session_id] = map[s.session_id] ? Math.min(map[s.session_id], start) : start;
      }
    }
    return map;
  }, [historicalSessions]);

  const liveSessionRows = useMemo(() => (
    Object.entries(heartbeats)
      .filter(([, hb]: [string, any]) => getPlatform(hb) !== 'server')
      .map(([pid, hb]: [string, any]) => {
        const p = hb.player || {};
        // Prefer the persisted session start; fall back to the heartbeat's own
        // session_start, then to the prefix encoded in the session/player id
        // (a unix timestamp), and only last to the current heartbeat time.
        const idPrefix = Number(String(hb.session_id || pid).split('-')[0]);
        const start = sessionStartById[hb.session_id]
          ?? hb.session_start
          ?? (Number.isFinite(idPrefix) && idPrefix > 1_000_000_000 ? idPrefix : undefined)
          ?? hb.timestamp;
        return {
          player_id: pid,
          display_name: hb.display_name,
          color: hb.color,
          session_id: hb.session_id,
          platform: getPlatform(hb) || 'unknown',
          start_time: start,
          duration: 0,
          scenes_visited: p.scene ? [p.scene] : [],
          scene: p.scene,
          avg_fps: p.fps ?? 0,
          avg_mem: p.memory_mb ?? 0,
          live: true,
        };
      })
  ), [heartbeats, sessionStartById]);

  // player_id -> geo, joined from geoPlayers. Used both to enrich session rows
  // for display and to resolve a session's country for the country filter.
  const geoByPlayer = useMemo(() => {
    const map: Record<string, { city?: string; country?: string; country_code?: string; display_name?: string; color?: string }> = {};
    for (const g of geoPlayers) {
      if (g.player_id && !map[g.player_id]) {
        map[g.player_id] = {
          city: g.city, country: g.country, country_code: g.country_code,
          display_name: g.display_name, color: g.color,
        };
      }
    }
    return map;
  }, [geoPlayers]);

  // A session's ISO country code: from the row (server-enriched) or the geo join.
  const countryCodeForSession = (session: any): string => {
    const direct = String(session.country_code || '').toUpperCase();
    if (direct) return direct;
    const geo = session.player_id ? geoByPlayer[session.player_id] : undefined;
    return String(geo?.country_code || '').toUpperCase();
  };

  const filteredHistoricalSessions = useMemo(() => {
    const liveIds = new Set(liveSessionRows.map((s) => s.session_id).filter(Boolean));
    const merged = [
      ...liveSessionRows,
      // Drop persisted rows that are still live (avoid duplicate of the same session).
      ...historicalSessions.filter((s) => !liveIds.has(s.session_id)),
    ];
    // Min-duration excludes very short (bootup-only) sessions, but live rows
    // (still in flight, duration 0) are always kept.
    return merged.filter((session) => (
      platformAllowed(session)
      && sceneAllowed(session)
      && (selectedCountry === 'all' || countryCodeForSession(session) === selectedCountry)
      && (session.live || minDuration <= 0 || sessionDuration(session) >= minDuration)
    ));
  }, [historicalSessions, liveSessionRows, selectedPlatforms, selectedSceneFilter, selectedCountry, geoByPlayer, minDuration]);

  const sceneFilterOptions = useMemo<SceneFilterOption[]>(() => {
    return availableSceneFilters
      .map((scene) => {
        const sessionsForScene = filteredHistoricalSessions.filter((session) => {
          const ss = sessionScenes(session);
          return ss.length === 0 || ss.includes(scene);
        });
        return {
          scene,
          sessions: sessionsForScene.length,
          playTime: sessionsForScene.reduce((sum, session) => sum + sessionDuration(session), 0),
        };
      })
      .sort((a, b) => (b.sessions - a.sessions) || (b.playTime - a.playTime) || a.scene.localeCompare(b.scene));
  }, [availableSceneFilters, filteredHistoricalSessions]);

  // Country options for the filter: every geolocatable country across the
  // current session set, with a count. Built independent of selectedCountry so
  // the user can switch between countries freely.
  const availableCountries = useMemo<CountryFilterOption[]>(() => {
    const liveIds = new Set(liveSessionRows.map((s) => s.session_id).filter(Boolean));
    const all = [...liveSessionRows, ...historicalSessions.filter((s) => !liveIds.has(s.session_id))];
    const byCode = new Map<string, { code: string; label: string; sessions: number }>();
    for (const s of all) {
      const code = countryCodeForSession(s);
      if (!code) continue;
      const country = String(s.country || geoByPlayer[s.player_id]?.country || '').trim();
      const label = [countryFlag(code), country || code].filter(Boolean).join(' ');
      const cur = byCode.get(code) || { code, label, sessions: 0 };
      cur.sessions += 1;
      byCode.set(code, cur);
    }
    return [...byCode.values()].sort((a, b) => b.sessions - a.sessions || a.code.localeCompare(b.code));
  }, [historicalSessions, liveSessionRows, geoByPlayer]);

  const filteredDashboardSessions = useMemo(() => (
    filteredHistoricalSessions.filter(isDashboardSession)
  ), [filteredHistoricalSessions]);

  // Aggregate stats for the heatmap landing panel (shown instead of a bare
  // "select a scene" prompt). Reuses the already-filtered dashboard sessions.
  const heatmapSummary = useMemo(() => {
    const sessions = filteredDashboardSessions;
    const totalSessions = sessions.length;
    const totalPlaySeconds = sessions.reduce((sum, s) => sum + sessionDuration(s), 0);
    const fpsValues = sessions.map((s) => Number(s.avg_fps)).filter(Number.isFinite);
    const avgFps = fpsValues.reduce((sum, f) => sum + f, 0) / (fpsValues.length || 1);
    const livePlayers = sessions.filter((s) => s.live).length;
    const topScenes = [...sceneFilterOptions].slice(0, 5);
    return { totalSessions, totalPlaySeconds, avgFps, livePlayers, sceneCount: sceneFilterOptions.length, topScenes };
  }, [filteredDashboardSessions, sceneFilterOptions]);

  const heatmapHotzones = useMemo(() => {
    if (!heatmapTargetScene) return [];
    const sessionIds = new Set(
      filteredDashboardSessions
        .filter((session) => sessionScenes(session).includes(heatmapTargetScene))
        .map((session) => session.session_id)
        .filter(Boolean)
    );
    return hotzones
      .filter((hz) => hz.session_id && sessionIds.has(hz.session_id))
      .sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
  }, [heatmapTargetScene, filteredDashboardSessions, hotzones]);

  const filteredGeoPlayers = useMemo(() => {
    const allowedPlayers = new Set(filteredDashboardSessions.map((session) => session.player_id).filter(Boolean));
    return geoPlayers.filter((player) => (
      !player.historical
      && player.player_id
      && allowedPlayers.has(player.player_id)
    ));
  }, [geoPlayers, filteredDashboardSessions]);

  const filteredHeatmapData = useMemo(() => (
    (heatmapData ?? []).filter((item) => platformAllowed(item) && sceneAllowed(item))
  ), [heatmapData, selectedPlatforms, selectedSceneFilter]);

  useEffect(() => {
    if (viewport3DPreloaded.current) return;
    if (activeTab !== 'live' && !selectedPlayerId && Object.keys(heartbeats).length === 0) return;
    viewport3DPreloaded.current = true;
    const preload = () => { loadViewport3D().catch(() => { viewport3DPreloaded.current = false; }); };
    const idle = window.requestIdleCallback?.(preload, { timeout: 2500 });
    if (idle == null) {
      const timer = window.setTimeout(preload, 400);
      return () => window.clearTimeout(timer);
    }
    return () => window.cancelIdleCallback?.(idle);
  }, [activeTab, selectedPlayerId, heartbeats]);

  useEffect(() => {
    if (activeTab === 'heatmap' && heatmapTargetScene) {
      getHeatmap(heatmapTargetScene, heatmapRes)
        .then((d) => setHeatmapData(Array.isArray(d) ? d : []))
        .catch(() => setHeatmapData([]));
    } else if (activeTab === 'heatmap') {
      setHeatmapData([]);
    }
  }, [activeTab, heatmapTargetScene, heatmapRes]);

  useEffect(() => {
    if (activeTab !== 'mapa') return;
    loadGeoPlayers();
    const interval = setInterval(loadGeoPlayers, 30000);
    return () => clearInterval(interval);
  }, [activeTab, loadGeoPlayers]);

  const togglePlatform = (platform: string) => {
    setSelectedPlatforms((prev) => {
      const next = new Set(prev);
      if (next.has(platform)) next.delete(platform);
      else next.add(platform);
      return next;
    });
  };

  const pids = Object.keys(filteredHeartbeats);
  const hasLive = pids.length > 0;
  const canShowSpatialLiveView = hasLive || !!selectedPlayerId;
  // Peers = other live players besides the active one. Drives the PEERS toggle's
  // enabled state (no peers → nothing to show, so the button reads disabled).
  const otherPeerCount = Math.max(0, pids.length - 1);

  useEffect(() => {
    if (pids.length > 0) setLastLivePlayerCount(pids.length);
  }, [pids.length]);

  const activeFilterCount =
    (selectedSceneFilter !== 'all' ? 1 : 0) +
    (selectedCountry !== 'all' ? 1 : 0) +
    (KNOWN_PLATFORMS.filter((p) => p !== 'server').length - [...selectedPlatforms].filter((p) => p !== 'server').length > 0 ? 1 : 0) +
    (minDuration !== DEFAULT_HISTORY_MIN_DURATION ? 1 : 0);

  const playerCountLabel = pids.length > 0
    ? `${pids.length} ${pids.length === 1 ? 'player' : 'players'}`
    : lastLivePlayerCount > 0
      ? `${lastLivePlayerCount} last live`
      : `${filteredDashboardSessions.length} sessions`;

  // A player the user explicitly selected/follows is resolved against the
  // unfiltered heartbeat map, not filteredHeartbeats: scene/platform list filters
  // must not yank the followed player out from under you. On a scene change the
  // client can briefly report a scene (or a platform string) the active filters
  // exclude — resolving against filteredHeartbeats here made activeHb go
  // undefined and bounced the 3D view back to the home/wait screen.
  const explicitActiveId = selectedPlayerId && heartbeats[selectedPlayerId] ? selectedPlayerId : null;
  const activeId = explicitActiveId || pids[0];
  const activeHb = heartbeats[activeId] || filteredHeartbeats[activeId];
  const activeLabel = activeHb?.display_name || activeId;
  const activeHistory = history[activeId];
  const focusedGeo = useMemo(() => (
    focusPlayerId ? geoPlayers.find((player) => player.player_id === focusPlayerId) : undefined
  ), [focusPlayerId, geoPlayers]);
  // player_id -> {city, country} so player lists can show location instead of
  // the raw id. Geo data only lives on geoPlayers, not on the heartbeat.
  // History sessions enriched with geo (city/country) and tags (display_name,
  // color) joined by player_id, so the session list shows location + the player's
  // tag — and re-renders the moment a tag is saved (loadGeoPlayers refreshes the
  // source). Only fills fields the row doesn't already carry.
  const historySessionsWithGeo = useMemo(() => (
    filteredHistoricalSessions.map((s) => {
      const geo = s.player_id ? geoByPlayer[s.player_id] : undefined;
      if (!geo) return s;
      return {
        ...s,
        city: s.city || geo.city,
        country: s.country || geo.country,
        country_code: s.country_code || geo.country_code,
        display_name: s.display_name || geo.display_name,
        color: s.color || geo.color,
      };
    })
  ), [filteredHistoricalSessions, geoByPlayer]);
  const staleAge = activeHb ? (activeHb.timestamp ? (Date.now() - activeHb.timestamp * 1000) / 1000 : 0) : 0;
  // "Desconocida" is the placeholder the game emits for a tick or two while a
  // scene is loading (ANNAV2_Thread player_data default). Treat it as "no scene"
  // so we don't try to load a /game-assets/Desconocida.glb or flicker the scene.
  // The live view always follows the *real* scene of the player you're tracking,
  // never the scene filter. The filter scopes the players list and birdseye map,
  // but pinning liveSceneName to selectedSceneFilter froze the 3D view (model +
  // geometry stream) on that scene, so following a player across scenes left the
  // viewport stuck on the first one. (Same lesson as the platform/scene filters
  // not being allowed to yank the followed player out from under you.)
  const rawLiveScene = activeHb?.player?.scene || '';
  const liveSceneName = rawLiveScene === 'Desconocida' ? '' : rawLiveScene;
  const birdseyeSceneName = selectedSceneFilter === 'all' ? '' : selectedSceneFilter;

  const safePos = (p: any): [number, number, number] => {
    if (Array.isArray(p) && p.length >= 3) {
      return [Number(p[0]), Number(p[1]), Number(p[2])];
    }
    return [0, 0, 0];
  };

  const liveGhostMarkers = showLiveGhosts
    ? Object.values(filteredHeartbeats).filter((h: any) => h.player_id !== activeId)
    : [];

  const clearPlayerSelection = () => {
    setSelectedPlayerId(null);
    setFocusPlayerId(null);
    setFollowPlayer(false);
    setShowTagEditor(false);
    setBirdseyeDetailId(null);
    const url = new URL(window.location.href);
    url.searchParams.delete('player');
    window.history.replaceState(null, '', `${url.pathname}${url.search}${url.hash}`);
  };

  // The 3D viewport element, reused inline and inside the fullscreen overlay.
  const viewport3D = (
    <Suspense fallback={<LazyPanelFallback label="Cargando 3D…" />}>
      <Viewport3D
        activeId={activeId}
        heartbeats={heartbeats}
        hotzones={hotzones}
        sessions={historySessionsWithGeo}
        onSelectSession={handleSelectHistorySession}
        onDownloadHotzone={handleDownloadHotzone}
        onPlayHotzone={handlePlayHotzone}
        setActiveTab={setActiveTab}
        position={activeHb ? safePos(activeHb.player.position) : [0, 0, 0]}
        yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
        pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
        roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
        trail={activeHistory?.trail || []}
        follow={followPlayer}
        wireframe={false}
        sceneName={liveSceneName}
        staleAge={staleAge}
        liveGhosts={liveGhostMarkers}
        label={activeHb ? (activeHb.display_name || activeId?.slice(0, 8)) : undefined}
        color={activeHb?.color || undefined}
        hud={activeHb ? {
          fps: activeHb.player?.fps,
          scene: activeHb.player?.scene,
          playerId: activeId,
          displayName: activeHb.display_name,
          sessionId: activeHb.session_id,
          platform: getPlatform(activeHb) || undefined,
          memoryMb: activeHb.player?.memory_mb,
          mode: activeHb.player?.mode,
          tick: activeHb.player?.tick,
          peers: pids.length,
          staleAge,
        } : null}
        onUserInteract={() => setFollowPlayer(false)}
      />
    </Suspense>
  );

  const birdseyeMap = (
    <LiveMap
      ghosts={liveGhosts}
      sceneName={birdseyeSceneName}
      activePlayerId={activeId}
      onSelectGhost={(pid) => setBirdseyeDetailId(pid)}
    />
  );

  // Heatmap summary stats — the cards + top-scenes list. Reused for both the
  // "no scene selected" landing fallback and the dedicated Stats sub-tab
  // (FD-223). Only the stats that correspond to the heatmap, nothing else.
  const heatmapStatsPanel = (
    <div className="h-full overflow-y-auto bg-bg-primary p-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
          <div className="text-[0.625rem] font-black uppercase text-text-muted">Sessions</div>
          <div className="text-2xl font-black text-accent">{heatmapSummary.totalSessions}</div>
          {heatmapSummary.livePlayers > 0 && (
            <div className="text-[0.625rem] font-black uppercase text-success">{heatmapSummary.livePlayers} live</div>
          )}
        </div>
        <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
          <div className="text-[0.625rem] font-black uppercase text-text-muted">Play time</div>
          <div className="text-2xl font-black text-text-primary">{formatPlayTime(heatmapSummary.totalPlaySeconds)}</div>
        </div>
        <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
          <div className="text-[0.625rem] font-black uppercase text-text-muted">Avg FPS</div>
          <div className="text-2xl font-black" style={{ color: fpsColor(heatmapSummary.avgFps) }}>
            {heatmapSummary.avgFps.toFixed(1)}
          </div>
        </div>
        <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
          <div className="text-[0.625rem] font-black uppercase text-text-muted">Scenes</div>
          <div className="text-2xl font-black text-text-primary">{heatmapSummary.sceneCount}</div>
        </div>
      </div>
    </div>
  );

  return (
    <DashboardLayout
      onLogout={onLogout}
      isConnected={isConnected}
      activeTab={activeTab}
      setActiveTab={setActiveTab}
      playerCount={pids.length}
      playerCountLabel={playerCountLabel}
      onPlayersClick={() => setShowPlayerSheet(true)}
      activePlayerMeta={activeHb ? (
        <div className="hidden min-w-0 items-center gap-2 border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-bold md:flex">
          <button
            type="button"
            onClick={() => { setActiveTab('live'); setLiveView('3d'); }}
            title="Player activo — ver en 3D"
            className="flex min-w-0 items-center gap-2 hover:text-accent"
          >
            {activeHb.color && (
              <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: activeHb.color }} />
            )}
            <span className="max-w-[120px] truncate">{activeLabel}</span>
            <span className="text-text-muted/60">·</span>
            <span className="max-w-[90px] truncate text-accent">{activeHb.player?.scene || '—'}</span>
            <span className="text-text-muted/60">·</span>
            <span style={{ color: fpsColor(Number(activeHb.player?.fps) || 0) }}>
              {formatFpsLabel(activeHb.player?.fps)}
            </span>
            {activeHb.player?.memory_mb != null && (
              <>
                <span className="text-text-muted/60">·</span>
                <span className="text-text-muted">{Math.round(Number(activeHb.player.memory_mb))} MB</span>
              </>
            )}
            {activeHb.player?.focused === false && (
              <span className="uppercase text-text-muted/80" title="En segundo plano">bg</span>
            )}
          </button>
          <button
            type="button"
            onClick={() => { setFocusPlayerId(activeId); setShowTagEditor(true); }}
            title="Etiquetar player"
            aria-label="Etiquetar player"
            className="shrink-0 text-text-muted hover:text-accent"
          >
            <Tag size={12} />
          </button>
          {explicitActiveId && (
            <button
              type="button"
              onClick={clearPlayerSelection}
              title="Deseleccionar player"
              aria-label="Deseleccionar player"
              className="shrink-0 text-text-muted hover:text-danger"
            >
              <X size={12} />
            </button>
          )}
        </div>
      ) : undefined}
      showSettings={showSettings}
      onToggleSettings={() => setShowSettings(!showSettings)}
      settingsPanel={
        <div>
          <NotificationSettings />
        </div>
      }
      playerFocus={
        focusPlayerId ? (
          <PlayerFocus
            playerId={focusPlayerId}
            displayName={filteredHeartbeats[focusPlayerId]?.display_name || focusedGeo?.display_name}
            country={focusedGeo?.country}
            countryCode={focusedGeo?.country_code}
            onClear={clearPlayerSelection}
            onTagClick={() => setShowTagEditor(!showTagEditor)}
          />
        ) : undefined
      }
      dashboardVersion={DASHBOARD_BUILD_VERSION || health?.dashboard_version}
      dashboardDeployedAt={health?.dashboard_deployed_at}
      latestPublished={health?.latest_published}
      headerControls={
        <div className="flex shrink-0 items-center gap-1.5">
          <button
            onClick={() => {
              // Mobile: open the slide-in overlay. Desktop (xl+): toggle the
              // docked sidebar. One handler — the overlay is xl:hidden and the
              // sidebar hidden below xl, so each viewport reacts to the right one.
              setShowFilters(true);
              setFiltersCollapsed(!filtersCollapsed);
            }}
            className="flex shrink-0 items-center gap-1.5 border-2 border-black bg-bg-primary px-2.5 py-1.5 text-[0.625rem] font-black uppercase hover:bg-accent hover:text-black"
            title="Filtros"
          >
            <SlidersHorizontal size={14} />
            <span className="hidden sm:inline">Filtros</span>
            {activeFilterCount > 0 && (
              <span className="flex h-4 min-w-4 items-center justify-center bg-accent px-1 text-[0.5625rem] text-black">
                {activeFilterCount}
              </span>
            )}
          </button>
          {activeFilterCount > 0 && (
            <button
              onClick={resetFilters}
              className="flex shrink-0 items-center justify-center border-2 border-black bg-bg-primary p-1.5 hover:bg-danger hover:text-black"
              title="Reset filtros"
              aria-label="Reset filtros"
            >
              <RotateCcw size={14} />
            </button>
          )}
        </div>
      }
      secondaryNav={activeTab === 'live' ? (
        <div className="flex">
          {([
            { id: 'dashboard', label: 'Dashboard', enabled: true },
            { id: 'birdseye', label: 'Birdseye', enabled: canShowSpatialLiveView },
            { id: '3d', label: '3D', enabled: canShowSpatialLiveView },
          ] as const).map((v) => (
            <button
              key={v.id}
              onClick={() => v.enabled && setLiveView(v.id)}
              onMouseEnter={() => { if (v.id === '3d') loadViewport3D().catch(() => {}); }}
              onFocus={() => { if (v.id === '3d') loadViewport3D().catch(() => {}); }}
              onTouchStart={() => { if (v.id === '3d') loadViewport3D().catch(() => {}); }}
              disabled={!v.enabled}
              className={`subtab-btn ${liveView === v.id ? 'subtab-btn-active' : ''}`}
            >
              {v.label}
            </button>
          ))}
        </div>
      ) : undefined}
    >
      <Toaster position="bottom-right" />

      {/* Global tag editor — lets you tag a player from any tab (e.g. History).
          The mapa tab renders its own inline instance, so skip it there to avoid
          a duplicate. onSaved refreshes geoPlayers, which flows into the history
          rows' display_name/color immediately. */}
      {showTagEditor && focusPlayerId && activeTab !== 'mapa' && (
        <div className="fixed right-4 top-16 z-[8000] w-80 max-w-[90vw]">
          <PlayerTagEditor
            playerId={focusPlayerId}
            onSaved={loadGeoPlayers}
            onClose={() => { setShowTagEditor(false); setFocusPlayerId(null); }}
          />
        </div>
      )}

      <FiltersDrawer
        open={showFilters}
        onClose={() => setShowFilters(false)}
        platforms={availablePlatforms}
        selectedPlatforms={selectedPlatforms}
        onTogglePlatform={togglePlatform}
        platformCounts={platformCounts}
        scenes={sceneFilterOptions}
        selectedScene={selectedSceneFilter}
        onSelectScene={setSelectedSceneFilter}
        countries={availableCountries}
        selectedCountry={selectedCountry}
        onSelectCountry={setSelectedCountry}
        minDuration={minDuration}
        onSetMinDuration={setMinDuration}
        onReset={resetFilters}
      />

      <PlayerBottomSheet
        open={showPlayerSheet}
        onClose={() => setShowPlayerSheet(false)}
        players={Object.values(filteredHeartbeats)}
        geoByPlayer={geoByPlayer}
        history={history}
        activeId={explicitActiveId}
        onSelect={(pid) => {
          setSelectedPlayerId(pid);
          setActiveTab('live');
          setLiveView('3d');
          setFollowPlayer(true);
          setShowPlayerSheet(false);
        }}
      />

      {/* CSS fullscreen overlay for the 3D canvas (works on mobile). */}
      {fs3d && (
        <div className="fixed inset-0 z-[9999] bg-black flex flex-col">
          <button
            onClick={() => setFs3d(false)}
            className="absolute top-3 right-3 z-10 p-2 border-2 border-white/40 bg-black/60 text-white"
            aria-label="Close fullscreen"
          >
            <X size={24} />
          </button>
          <div className="relative flex-1 min-h-0">
            {viewport3D}
            {showLiveCharts && activeHistory && (
              <div className="absolute top-3 left-3 z-10 h-28 w-72 max-w-[60vw] border-2 border-black bg-bg-card/90 p-2 shadow-[3px_3px_0px_0px_black]">
                <LiveCombinedChart history={activeHistory} />
              </div>
            )}
          </div>
        </div>
      )}

      {fsBirdseye && (
        <div className="fixed inset-0 z-[9999] bg-black flex flex-col">
          <button
            onClick={() => setFsBirdseye(false)}
            className="absolute top-3 right-3 z-10 p-2 border-2 border-white/40 bg-black/60 text-white"
            aria-label="Close fullscreen map"
          >
            <X size={24} />
          </button>
          <div className="relative flex-1 min-h-0">
            {birdseyeMap}
          </div>
        </div>
      )}
      
      {/* Content + docked desktop filters sidebar. The content column scrolls;
          the sidebar is a fixed-width docked column on xl+ (overlay on mobile). */}
      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden">
      {activeTab === 'live' && (
        <div className="flex flex-col h-full min-h-0">
          {/* View area fills all remaining space; the view switcher now lives in
              the secondary nav above the bottom bar. */}
          <div className="flex-1 min-h-0 relative">
            {liveView === 'dashboard' ? (
              /* Stripe layout: charts on top, info cards below. */
              <div className="flex h-full min-h-0 flex-col">
                {/* Top stripe: live combined FPS/Memory chart, else Sessions/day */}
                <CollapsibleCard
                  title="Performance Charts"
                  storageKey="live_charts_collapsed"
                  defaultOpen={true}
                  resizable={true}
                  initialHeight={320}
                  className="shrink-0 border-x-0 border-t-0"
                >
                  <div className="flex h-full flex-col bg-bg-card/40">
                    <div className="flex shrink-0">
                      {(activeHistory
                        ? ([['live', 'FPS / Memoria'], ['sessions', 'Sesiones'], ['versions', 'Versiones']] as const)
                        : ([['sessions', 'Sesiones'], ['versions', 'Versiones']] as const)
                      ).map(([id, label]) => {
                        const effectiveTab = activeHistory ? dashStripeTab : (dashStripeTab === 'live' ? 'sessions' : dashStripeTab);
                        return (
                          <button
                            key={id}
                            onClick={() => setDashStripeTab(id)}
                            className={`subtab-btn ${effectiveTab === id ? 'subtab-btn-active' : ''}`}
                          >
                            {label}
                          </button>
                        );
                      })}
                    </div>
                    <div className="min-h-0 flex-1 p-3">
                      {activeHistory && dashStripeTab === 'live' ? (
                        <LiveCombinedChart history={activeHistory} />
                      ) : dashStripeTab === 'versions' ? (
                        <CommitsFpsChart sessions={filteredDashboardSessions} commits={commits} />
                      ) : (
                        <SessionsPerDayChart sessions={filteredDashboardSessions} />
                      )}
                    </div>
                  </div>
                </CollapsibleCard>
                {/* Bottom stripe: info cards (historical summary) */}
                <div className="min-h-0 flex-1 overflow-y-auto">
                  <div className="p-4 sm:p-6 pb-0">
                  </div>
                  <HomeStats sessions={filteredDashboardSessions} serverStats={serverStats} />
                </div>
              </div>
            ) : !activeHb ? (
              <LiveWaitTicker items={[
                { label: 'Sesiones totales', value: String(heatmapSummary.totalSessions) },
                { label: 'Tiempo jugado', value: formatPlayTime(heatmapSummary.totalPlaySeconds) },
                { label: 'FPS promedio', value: heatmapSummary.avgFps.toFixed(1) },
                { label: 'Escenas', value: String(heatmapSummary.sceneCount) },
                ...(heatmapSummary.topScenes[0] ? [{ label: 'Escena más jugada', value: heatmapSummary.topScenes[0].scene }] : []),
                ...(availableCountries[0] ? [{ label: 'País más activo', value: availableCountries[0].label }] : []),
                ...(Number(serverStats?.unique_players_total) > 0 ? [{ label: 'Players únicos', value: String(serverStats?.unique_players_total) }] : []),
              ]} />
            ) : liveView === '3d' ? (
              <div className="flex h-full min-h-0 flex-col">
                {/* 3D-only control bar */}
                <div className="shrink-0 flex flex-wrap items-center gap-1 p-2 border-b-2 border-black bg-bg-card/60">
                  <RetroButton variant={followPlayer ? 'primary' : 'secondary'} onClick={() => setFollowPlayer(!followPlayer)} className="py-1 px-2 text-[0.625rem]">FOLLOW</RetroButton>
                  <RetroButton
                    variant={showLiveGhosts && otherPeerCount > 0 ? 'primary' : 'secondary'}
                    onClick={() => otherPeerCount > 0 && setShowLiveGhosts(!showLiveGhosts)}
                    disabled={otherPeerCount === 0}
                    title={otherPeerCount === 0 ? 'No other peers online' : `${otherPeerCount} peer(s) online`}
                    className={`py-1 px-2 text-[0.625rem] ${otherPeerCount === 0 ? 'opacity-40 cursor-not-allowed' : ''}`}
                  >
                    PEERS{otherPeerCount > 0 ? ` ${otherPeerCount}` : ''}
                  </RetroButton>
                  <RetroButton variant={showLiveCharts ? 'primary' : 'secondary'} onClick={() => setShowLiveCharts(!showLiveCharts)} className="py-1 px-2 text-[0.625rem]">CHARTS</RetroButton>
                  <RetroButton variant="secondary" onClick={() => setFs3d(true)} className="py-1 px-2" title="Fullscreen 3D"><Maximize2 size={14} /></RetroButton>
                </div>
                <div className="relative flex-1 min-h-0">
                  {viewport3D}
                </div>
                {/* Bottom panel: large live FPS+RAM chart plus an explicit metric
                    strip. Replaces the old redundant accordion — RAM is now a
                    first-class readout instead of hidden in the chart's right axis. */}
                {showLiveCharts && (
                  <div className="shrink-0 border-t-2 border-black bg-bg-card/80">
                    <div className="grid grid-cols-2 gap-2 px-3 pt-2 text-[0.625rem] font-mono sm:grid-cols-4 lg:grid-cols-6">
                      <Info label="FPS" value={`${formatFpsLabel(activeHb?.player?.fps).replace(' FPS', '')}${activeHb?.player?.focused === false ? ' (bg)' : ''}`} />
                      <Info label="RAM" value={activeHb?.player?.memory_mb != null ? `${Math.round(activeHb.player.memory_mb)} MB` : '—'} />
                      <Info label="Scene" value={activeHb?.player?.scene || '-'} />
                      <Info label="Platform" value={getPlatform(activeHb) || '-'} />
                      <Info label="Peers" value={otherPeerCount} />
                      <Info label="Latency" value={`${staleAge.toFixed(1)}s`} />
                    </div>
                    <div className="h-40 px-2 pb-2 pt-1">
                      <LiveCombinedChart history={activeHistory} />
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <>
                {birdseyeMap}

                <button
                  type="button"
                  onClick={() => setFsBirdseye(true)}
                  className="absolute right-3 top-3 z-10 border-2 border-black bg-bg-card/90 p-2 hover:bg-accent hover:text-black"
                  title="Fullscreen map"
                  aria-label="Fullscreen map"
                >
                  <Maximize2 size={16} />
                </button>

                {/* Live chart overlay for the active player — shown by default
                    (top-left), like the 3D view. Hidden if charts are toggled
                    off or there's no history yet. */}
                {showLiveCharts && activeHistory && !birdseyeDetailId && (
                  <div className="absolute top-3 left-3 z-10 h-28 w-60 max-w-[55vw] border-2 border-black bg-bg-card/90 p-2 shadow-[3px_3px_0px_0px_black] backdrop-blur-sm">
                    <div className="mb-1 truncate text-[0.5625rem] font-black uppercase text-accent">{activeLabel || activeId?.slice(0, 12)}</div>
                    <div className="h-[calc(100%-1rem)]">
                      <LiveCombinedChart history={activeHistory} />
                    </div>
                  </div>
                )}

                {birdseyeDetailId && (() => {
                  const hb = filteredHeartbeats[birdseyeDetailId];
                  const hist = history[birdseyeDetailId];
                  return (
                    <div className="absolute right-3 top-3 z-20 w-64 max-w-[80vw] border-2 border-black bg-bg-card/95 p-3 shadow-[3px_3px_0px_0px_black]">
                      <div className="mb-2 flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="truncate text-xs font-black text-accent">{hb?.display_name || birdseyeDetailId.slice(0, 12)}</div>
                          {hb?.display_name && <div className="truncate text-[0.5625rem] text-text-muted">{birdseyeDetailId.slice(0, 12)}</div>}
                          <div className="truncate text-[0.625rem] text-text-muted">{hb?.player?.scene || 'scene —'}</div>
                        </div>
                        <button
                          onClick={() => setBirdseyeDetailId(null)}
                          className="shrink-0 border-2 border-black bg-bg-primary px-1.5 py-0.5 text-[0.625rem] font-black hover:bg-danger hover:text-black"
                          aria-label="Close"
                        >
                          <X size={12} />
                        </button>
                      </div>
                      <div className="h-28">
                        <LiveCombinedChart history={hist} />
                      </div>
                      <HotzoneList
                        sessions={hb ? [{
                          player_id: birdseyeDetailId,
                          session_id: hb.session_id,
                          display_name: hb.display_name,
                          scene: hb.player?.scene,
                        }] : []}
                        // HotzoneList renders every row it's given (it only uses
                        // sessions for name lookup), so scope to this player here.
                        hotzones={hotzones.filter((hz: any) =>
                          hz.player_id === birdseyeDetailId || (hb?.session_id && hz.session_id === hb.session_id)
                        )}
                        onDownloadHotzone={handleDownloadHotzone}
                        onPlayHotzone={handlePlayHotzone}
                        onTagPlayer={(pid) => { setFocusPlayerId(pid); setShowTagEditor(true); }}
                        compact
                      />
                      <div className="mt-2 flex gap-2">
                        <RetroButton
                          variant="primary"
                          onClick={() => {
                            setSelectedPlayerId(birdseyeDetailId);
                            setBirdseyeDetailId(null);
                            setLiveView('3d');
                            setFollowPlayer(true);
                          }}
                          className="flex-1 py-1 text-[0.625rem]"
                        >
                          Ver 3D
                        </RetroButton>
                        <RetroButton
                          variant="secondary"
                          onClick={() => {
                            const session = historySessionsWithGeo.find(s => s.session_id === hb.session_id);
                            if (session) {
                              handleSelectHistorySession(session);
                              setActiveTab('history');
                            }
                          }}
                          className="flex-1 py-1 text-[0.625rem]"
                        >
                          Historial
                        </RetroButton>
                      </div>
                    </div>
                  );
                })()}
              </>
            )}
          </div>
        </div>
      )}

      {activeTab === 'mapa' && (
        <div className="flex h-full flex-col">
          {focusPlayerId && showTagEditor && (
            <PlayerTagEditor
              playerId={focusPlayerId}
              onSaved={loadGeoPlayers}
              onClose={() => setShowTagEditor(false)}
            />
          )}
          <Suspense fallback={<LazyPanelFallback label="Cargando mapa…" />}>
            <GlobeView
              players={filteredGeoPlayers}
              onSelectPlayer={(playerId) => {
                setFocusPlayerId(playerId);
                setShowTagEditor(true);
                window.history.replaceState(null, '', `?player=${encodeURIComponent(playerId)}`);
              }}
            />
          </Suspense>
        </div>
      )}

      {activeTab === 'heatmap' && (
        <div className="flex h-full flex-col gap-3 overflow-hidden p-4">
          {/* Mobile-only sub-tabs (top, like History): Escenas / Mapa / Stats
              swap the single visible pane. On desktop (xl+) the two columns
              show side by side and the stats live in the right column when no
              scene is selected, so no tab bar is needed there. */}
          <div className="flex border-2 border-black xl:hidden">
            <button
              type="button"
              onClick={() => setHeatmapView('scenes')}
              className={`subtab-btn ${heatmapView === 'scenes' ? 'subtab-btn-active' : ''}`}
            >
              Escenas
            </button>
            <button
              type="button"
              onClick={() => setHeatmapView('stats')}
              className={`subtab-btn ${heatmapView === 'stats' ? 'subtab-btn-active' : ''}`}
            >
              Stats
            </button>
            <button
              type="button"
              onClick={() => setHeatmapView('map')}
              disabled={!heatmapTargetScene}
              className={`subtab-btn ${heatmapView === 'map' ? 'subtab-btn-active' : ''} disabled:opacity-40 disabled:cursor-not-allowed`}
            >
              Mapa
            </button>
          </div>

          <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
          <RetroCard title="Scenes" className={`min-h-0 overflow-hidden ${heatmapView !== 'scenes' ? 'hidden xl:block' : ''}`}>
            <SceneIndex
              sessions={filteredDashboardSessions}
              scenes={availableSceneFilters}
              selectedScene={selectedSceneFilter}
              onSelectScene={(scene) => {
                setSelectedSceneFilter(scene);
                setHeatmapView('map');
              }}
            />
          </RetroCard>

          {/* Mobile: this pane is the Stats view. Desktop: hidden (stats render
              in the right column below when no scene is selected). */}
          <div className={`min-h-0 border-4 border-black shadow-retro overflow-hidden xl:hidden ${heatmapView === 'stats' ? '' : 'hidden'}`}>
            {heatmapStatsPanel}
          </div>

          <div className={`min-h-0 relative border-4 border-black shadow-retro overflow-hidden ${heatmapView !== 'map' ? 'hidden xl:block' : ''}`}>
            {!heatmapTargetScene ? (
              heatmapStatsPanel
            ) : (
            <>
            <div className="absolute left-3 top-3 z-10 flex max-w-[calc(100%-1.5rem)] flex-wrap items-end gap-3 border-2 border-black bg-bg-card/95 p-3 shadow-[2px_2px_0px_0px_black]">
              <div className="min-w-0">
                <div className="text-[0.625rem] font-black uppercase text-text-muted">Scene</div>
                <div className="max-w-48 truncate text-xs font-black text-accent">{heatmapTargetScene}</div>
              </div>
              <div className="shrink-0">
                <div className="mb-1 text-[0.625rem] font-bold uppercase tracking-[0.25em] text-text-muted">Res</div>
                <div className="flex items-center border-2 border-black">
                  <button
                    type="button"
                    onClick={() => setHeatmapRes((value) => Math.max(1, value - 1))}
                    className="bg-bg-primary px-2 py-1 text-xs font-black hover:bg-accent hover:text-black"
                  >
                    -
                  </button>
                  <span className="min-w-8 border-x-2 border-black bg-bg-primary px-2 py-1 text-center text-xs font-black">{heatmapRes}</span>
                  <button
                    type="button"
                    onClick={() => setHeatmapRes((value) => value + 1)}
                    className="bg-bg-primary px-2 py-1 text-xs font-black hover:bg-accent hover:text-black"
                  >
                    +
                  </button>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-2 text-[0.5rem] font-bold uppercase sm:grid-cols-4">
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-green-500" /> Low</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-yellow-500" /> Med</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-orange-500" /> High</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-red-500" /> Crit</div>
              </div>
            </div>
            <Suspense fallback={<LazyPanelFallback label="Cargando heatmap…" />}>
              <Heatmap3D
                data={filteredHeatmapData}
                resolution={heatmapRes}
                scene={heatmapTargetScene}
                hotzones={heatmapHotzones}
                onSelectHotzone={(hz) => handlePlayHotzone(hz.id)}
                onDownloadHotzone={(hz) => handleDownloadHotzone(hz.id, hz.display_name || hz.player_id || undefined)}
              />
            </Suspense>
            {heatmapHotzones.length > 0 && (
              <CollapsibleCard
                title="Hotzones"
                count={heatmapHotzones.length}
                storageKey="heatmap_hotzones_collapsed"
                defaultOpen={false}
                className="absolute bottom-3 right-3 z-10 w-72 max-w-[calc(100%-1.5rem)] bg-bg-card/95"
              >
                <div className="flex flex-col gap-1 p-2 max-h-40">
                  {heatmapHotzones.slice(0, 8).map((hz) => {
                    const label = hz.display_name || hz.player_id || 'hotzone';
                    const ts = Number(hz.timestamp || 0);
                    return (
                      <div
                        key={hz.id}
                        className="flex items-center gap-1 border-2 border-black bg-bg-primary text-[0.625rem] font-bold"
                      >
                        <button
                          type="button"
                          onClick={() => handlePlayHotzone(hz.id)}
                          className="flex min-w-0 flex-1 items-center justify-between gap-2 px-2 py-1 text-left hover:bg-accent hover:text-black"
                          title="Reproducir captura en Netlify"
                        >
                          <span className="min-w-0 truncate">
                            {label} · {hz.trigger_type || 'auto'}
                          </span>
                          <span className="flex shrink-0 items-center gap-1 text-[0.5625rem]">
                            {ts ? new Date(ts * 1000).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' }) : ''}
                            <Play size={12} fill="currentColor" />
                          </span>
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDeleteHotzone(hz.id, label)}
                          className="shrink-0 border-l-2 border-black px-2 py-1 text-text-muted hover:bg-danger hover:text-white"
                          title="Borrar hotzone"
                        >
                          <Trash2 size={12} />
                        </button>
                      </div>
                    );
                  })}
                </div>
              </CollapsibleCard>
            )}
            </>
            )}
          </div>
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div className="flex h-full flex-col gap-3 overflow-hidden p-4">
          {/* Mobile pane toggle: session list vs hotzones vs playback. */}
          <div className="flex border-2 border-black xl:hidden">
            <button
              type="button"
              onClick={() => setHistoryMobileView('list')}
              className={`subtab-btn ${historyMobileView === 'list' ? 'subtab-btn-active' : ''}`}
            >
              Sesiones
            </button>
            <button
              type="button"
              onClick={() => setHistoryMobileView('hotzones')}
              className={`subtab-btn ${historyMobileView === 'hotzones' ? 'subtab-btn-active' : ''}`}
            >
              Hotzones{hotzones.length ? ` (${hotzones.length})` : ''}
            </button>
            <button
              type="button"
              onClick={() => setHistoryMobileView('player')}
              disabled={!selectedSession}
              className={`subtab-btn ${historyMobileView === 'player' ? 'subtab-btn-active' : ''}`}
            >
              Reproducción
            </button>
          </div>

          <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
            {/* Left: live session list sidebar */}
            <RetroCard title="Sesiones" className={`min-h-0 overflow-hidden ${historyMobileView !== 'list' ? 'hidden xl:block' : ''}`}>
              <div className="h-full overflow-y-auto">
                <HistoricalTable
                  sessions={historySessionsWithGeo}
                  onSelectSession={handleSelectHistorySession}
                  selectedSessionId={selectedSession?.session_id}
                  onEditTag={(pid) => { setFocusPlayerId(pid); setShowTagEditor(true); }}
                  hotzonesBySession={hotzonesBySession}
                  onDownloadHotzone={handleDownloadHotzone}
                  onPlayHotzone={handlePlayHotzone}
                />
              </div>
            </RetroCard>

            {/* Mobile-only hotzones pane: captures ordered by date with scene + duration. */}
            <RetroCard title={`Hotzones${hotzones.length ? ` (${hotzones.length})` : ''}`} className={`min-h-0 overflow-hidden xl:hidden ${historyMobileView === 'hotzones' ? '' : 'hidden'}`}>
              <div className="h-full overflow-y-auto">
                <HotzoneList
                  sessions={historySessionsWithGeo}
                  hotzones={hotzones}
                  onDownloadHotzone={handleDownloadHotzone}
                  onDeleteHotzone={handleDeleteHotzone}
                  onPlayHotzone={handlePlayHotzone}
                  onTagPlayer={(pid) => { setFocusPlayerId(pid); setShowTagEditor(true); }}
                />
              </div>
            </RetroCard>

            {/* Right: playback */}
            <div className={`min-h-0 overflow-y-auto ${historyMobileView !== 'player' ? 'hidden xl:block' : ''}`}>
              {!selectedSession ? (
                <div className="min-h-full p-1">
                  <HistoryOverview sessions={historySessionsWithGeo} hotzones={hotzones} onDownloadHotzone={handleDownloadHotzone} onDeleteHotzone={handleDeleteHotzone} onPlayHotzone={handlePlayHotzone} onTagPlayer={(pid) => { setFocusPlayerId(pid); setShowTagEditor(true); }} />
                </div>
              ) : playbackLoading ? (
                <div className="flex h-full items-center justify-center">
                  <div className="flex items-center gap-3 text-xs font-black uppercase tracking-widest text-text-muted">
                    <span className="h-4 w-4 animate-spin border-2 border-text-muted border-t-accent rounded-full" />
                    Loading session…
                  </div>
                </div>
              ) : (
                <Suspense fallback={<LazyPanelFallback label="Cargando replay…" />}>
                  <SessionPlayback heartbeats={playbackData} session={selectedSession} />
                </Suspense>
              )}
            </div>
          </div>
        </div>
      )}
        </div>

        <FiltersSidebar
          collapsed={filtersCollapsed}
          onToggleCollapsed={() => setFiltersCollapsed(!filtersCollapsed)}
          platforms={availablePlatforms}
          selectedPlatforms={selectedPlatforms}
          onTogglePlatform={togglePlatform}
          platformCounts={platformCounts}
          scenes={sceneFilterOptions}
          selectedScene={selectedSceneFilter}
          onSelectScene={setSelectedSceneFilter}
          countries={availableCountries}
          selectedCountry={selectedCountry}
          onSelectCountry={setSelectedCountry}
          minDuration={minDuration}
          onSetMinDuration={setMinDuration}
          onReset={resetFilters}
        />
      </div>
    </DashboardLayout>
  );
}

function App() {
  const [token, setToken] = useState<string | null>(localStorage.getItem("odisea_token"));

  if (!token) {
    return <LoginScreen onLogin={(t) => {
      localStorage.setItem("odisea_token", t);
      setToken(t);
    }} />;
  }

  return <Dashboard onLogout={() => {
    localStorage.removeItem("odisea_token");
    setToken(null);
  }} />;
}

export default App;
