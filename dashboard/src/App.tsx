import { useState, useEffect, useMemo, useRef, useCallback, type ReactNode } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import {
  Bar,
  BarChart,
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
import { Viewport3D } from './components/Viewport3D';
import { Heatmap3D } from './components/Heatmap3D';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { SessionPlayback } from './components/SessionPlayback';
import { DashboardLayout } from './components/DashboardLayout';
import { PlayerBottomSheet } from './components/PlayerBottomSheet';
import { FiltersDrawer, FiltersSidebar, type SceneFilterOption } from './components/FiltersDrawer';
import { LiveCombinedChart } from './components/LiveCombinedChart';
import { RetroCard, RetroButton } from './components/retro';
import { GlobeView } from './components/GlobeView';
import { PlayerFocus } from './components/PlayerFocus';
import { PlayerTagEditor } from './components/PlayerTagEditor';
import { useTelemetry } from './hooks/useTelemetry';
import { useWebSocket } from './hooks/useWebSocket';
import { useLayoutPersistence } from './hooks/useLayoutPersistence';
import { getGeoPlayers, getHeatmap, getHistoricalSessions, getGhostData, getScenes, getGhostStats } from './api';
import {
  KNOWN_PLATFORMS,
  getPlatform,
  isDashboardSession,
  sessionScenes,
  sessionDuration,
  isUsefulSceneName,
} from './lib/filters';
import { Maximize2, X, SlidersHorizontal, RotateCcw, WifiOff } from 'lucide-react';

type Tab = 'live' | 'heatmap' | 'history' | 'mapa';

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
      <BarChart data={sessionsByDay}>
        <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
        <XAxis dataKey="date" stroke="#666" fontSize={10} tickFormatter={(v) => String(v).slice(5)} />
        <YAxis stroke="#666" fontSize={10} allowDecimals={false} />
        <Tooltip content={tooltip} />
        <Bar dataKey="count" fill="#7fd1ff" isAnimationActive={false} />
      </BarChart>
    </ResponsiveContainer>
  );
};

const countryFlag = (countryCode?: string | null): string => {
  const code = (countryCode || '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return '';
  return Array.from(code).map((char) => String.fromCodePoint(char.charCodeAt(0) + 127397)).join('');
};

const HistoryOverview = ({ sessions }: { sessions: any[] }) => {
  const cleanSessions = useMemo(() => sessions.filter(isDashboardSession), [sessions]);

  const fpsSeries = useMemo(() => (
    cleanSessions
      .filter((s) => Number(s.start_time) > 0)
      .sort((a, b) => Number(a.start_time) - Number(b.start_time))
      .map((s) => ({
        timestamp: Number(s.start_time),
        date: formatDateTime(Number(s.start_time)),
        avg_fps: Number(s.avg_fps) || 0,
      }))
  ), [cleanSessions]);

  const stats = useMemo(() => {
    const totalDuration = cleanSessions.reduce((sum, s) => sum + sessionDuration(s), 0);
    const fpsValues = cleanSessions.map((s) => Number(s.avg_fps)).filter(Number.isFinite);
    const avgFps = fpsValues.reduce((sum, fps) => sum + fps, 0) / (fpsValues.length || 1);
    const uniquePlayers = new Set(cleanSessions.map((s) => s.player_id).filter(Boolean)).size;
    const scenes = new Map<string, { scene: string; sessions: number; duration: number }>();
    const countries = new Map<string, { label: string; sessions: number }>();

    cleanSessions.forEach((session) => {
      sessionScenes(session).filter(isUsefulSceneName).forEach((scene) => {
        const current = scenes.get(scene) || { scene, sessions: 0, duration: 0 };
        current.sessions += 1;
        current.duration += sessionDuration(session);
        scenes.set(scene, current);
      });
      const code = String(session.country_code || '').toUpperCase();
      const country = String(session.country || '').trim();
      const key = code || country || 'unknown';
      const label = [countryFlag(code), code || country || 'Unknown'].filter(Boolean).join(' ');
      const current = countries.get(key) || { label, sessions: 0 };
      current.sessions += 1;
      countries.set(key, current);
    });

    return {
      avgFps,
      totalDuration,
      uniquePlayers,
      scenes: [...scenes.values()].sort((a, b) => b.sessions - a.sessions || b.duration - a.duration).slice(0, 5),
      countries: [...countries.values()].sort((a, b) => b.sessions - a.sessions).slice(0, 5),
    };
  }, [cleanSessions]);

  const fpsTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div className="font-black text-accent">{d.date}</div>
        <div>Avg FPS: {Number(d.avg_fps).toFixed(1)}</div>
      </div>
    );
  };

  return (
    <div className="flex min-h-full flex-col gap-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          { label: 'Sessions', value: cleanSessions.length.toString() },
          { label: 'Players', value: stats.uniquePlayers.toString() },
          { label: 'Play Time', value: formatPlayTime(stats.totalDuration) },
          { label: 'Avg FPS', value: stats.avgFps.toFixed(1), color: fpsColor(stats.avgFps) },
        ].map((cell) => (
          <div key={cell.label} className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
            <div className="truncate text-xl font-black tracking-tighter" style={cell.color ? { color: cell.color } : undefined}>{cell.value}</div>
            <div className="mt-1 text-[0.5625rem] font-black uppercase text-text-muted">{cell.label}</div>
          </div>
        ))}
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-2">
        <RetroCard title="Sesiones por día" className="min-h-[220px]">
          <div className="h-52">
            <SessionsPerDayChart sessions={cleanSessions} />
          </div>
        </RetroCard>
        <RetroCard title="FPS por sesión" className="min-h-[220px]">
          <div className="h-52">
            {fpsSeries.length === 0 ? (
              <div className="flex h-full items-center justify-center text-xs italic text-text-muted">Sin datos de FPS</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
                <LineChart data={fpsSeries} margin={{ top: 6, right: 8, bottom: 0, left: -8 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
                  <XAxis dataKey="timestamp" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} tickFormatter={(v) => new Date(Number(v) * 1000).toISOString().slice(5, 10)} />
                  <YAxis stroke="#666" fontSize={10} width={28} />
                  <Tooltip content={fpsTooltip} />
                  <Line type="monotone" dataKey="avg_fps" stroke="#7fd1ff" dot={{ r: 3 }} strokeWidth={2} isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </RetroCard>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <RetroCard title="Escenas principales">
          <div className="flex flex-col gap-2">
            {stats.scenes.length === 0 ? (
              <div className="text-xs italic text-text-muted">Sin escenas filtradas</div>
            ) : stats.scenes.map((scene) => (
              <div key={scene.scene} className="flex items-center justify-between gap-3 border-2 border-black bg-bg-primary px-3 py-2">
                <span className="min-w-0 truncate text-xs font-black text-accent">{scene.scene}</span>
                <span className="shrink-0 text-[0.625rem] text-text-muted">{scene.sessions} · {formatPlayTime(scene.duration)}</span>
              </div>
            ))}
          </div>
        </RetroCard>
        <RetroCard title="Países">
          <div className="flex flex-col gap-2">
            {stats.countries.length === 0 ? (
              <div className="text-xs italic text-text-muted">Sin geolocalización en sesiones filtradas</div>
            ) : stats.countries.map((country) => (
              <div key={country.label} className="flex items-center justify-between gap-3 border-2 border-black bg-bg-primary px-3 py-2">
                <span className="truncate text-xs font-black text-text-primary">{country.label}</span>
                <span className="shrink-0 text-[0.625rem] text-text-muted">{country.sessions} sesiones</span>
              </div>
            ))}
          </div>
        </RetroCard>
      </div>
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

  // Clicking the chart selects the commit nearest to the clicked time.
  const onChartClick = (e: any) => {
    const t = e?.activeLabel;
    if (typeof t !== 'number' || commitLines.length === 0) return;
    const nearest = commitLines.reduce((best, c) =>
      Math.abs(c.timestamp - t) < Math.abs(best.timestamp - t) ? c : best
    );
    setSelectedSha(nearest.sha);
  };

  if (fpsSeries.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-xs italic text-text-muted">
        No session history yet
      </div>
    );
  }

  return (
    <div className="relative h-full w-full">
      <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
        <LineChart data={fpsSeries} margin={{ top: 4, right: 8, bottom: 0, left: -8 }} onClick={onChartClick}>
          <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
          <XAxis dataKey="timestamp" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} tickFormatter={(v) => new Date(Number(v) * 1000).toISOString().slice(5, 10)} />
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

      {/* Selected version metadata — moves with the chart cursor (click to pick
          the nearest commit). */}
      {selected && (
        <div className="pointer-events-none absolute left-2 top-2 max-w-[70%] border-2 border-black bg-bg-card/90 px-2 py-1.5 text-[0.5625rem] font-mono shadow-[2px_2px_0px_0px_black]">
          <div className="mb-0.5 font-black uppercase tracking-widest text-[#d29922]">
            Versión · <span className="text-[#f85149]">{selected.sha.slice(0, 7)}</span> · {new Date(selected.date).toISOString().slice(0, 10)}
          </div>
          <div className="whitespace-pre-wrap break-words text-text-primary">{selected.message.split('\n')[0]}</div>
          <div className="mt-1 text-text-muted/70">Click en el chart para elegir versión</div>
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
    }).filter((stat) => stat.sessions > 0);
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

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, isConnected, alerts, history, health } = useTelemetry();
  const { lastMessage } = useWebSocket();
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
  const [liveView, setLiveView] = useState<'dashboard' | 'birdseye' | '3d'>('birdseye');
  // CSS overlay fullscreen for the 3D canvas (NOT the browser Fullscreen API,
  // which is unreliable on mobile).
  const [fs3d, setFs3d] = useState(false);
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

  // Playback loading flag (history -> playback fetch).
  const [playbackLoading, setPlaybackLoading] = useState(false);

  // Heatmap State
  const [heatmapRes, setHeatmapRes] = useState(5);
  const [heatmapMobileView, setHeatmapMobileView] = useState<'scenes' | 'map'>('scenes');
  // History tab mobile pane toggle (session list vs playback), mirrors heatmap.
  const [historyMobileView, setHistoryMobileView] = useState<'list' | 'player'>('list');

  // Available scenes (fetched from backend, not hardcoded)
  const [scenes, setScenes] = useState<string[]>([]);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState<any[]>([]);
  const [selectedSession, setSelectedSession] = useState<any>(null);
  const [playbackData, setPlaybackData] = useState<any[]>([]);
  const [commits, setCommits] = useState<GitCommit[]>([]);
  const [serverStats, setServerStats] = useState<GhostStats>({});
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

  // Restore the default filters: all scenes, every platform except the headless
  // server.
  const resetFilters = () => {
    setSelectedPlatforms(new Set(KNOWN_PLATFORMS.filter((platform) => platform !== 'server')));
    setSelectedSceneFilter('all');
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
      ].filter(Boolean);

      toast.custom((t) => (
        <div className={`${t.visible ? 'opacity-100' : 'opacity-0'} border-4 border-black bg-bg-card p-3 font-mono text-xs text-text-primary shadow-[4px_4px_0px_0px_black] transition-opacity`}>
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
              <div className="mt-3 flex gap-2">
                {playerId !== 'unknown' && (
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
                    View live
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
    };
    loadSessions();
    const interval = setInterval(loadSessions, 10000);
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
      toast.error("Failed to load session data");
      setPlaybackData([]);
    } finally {
      setPlaybackLoading(false);
    }
  };

  const [followPlayer, setFollowPlayer] = useState(true);

  const availablePlatforms = useMemo(() => {
    return KNOWN_PLATFORMS;
  }, []);

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
  const liveSessionRows = useMemo(() => (
    Object.entries(heartbeats)
      .filter(([, hb]: [string, any]) => getPlatform(hb) !== 'server')
      .map(([pid, hb]: [string, any]) => {
        const p = hb.player || {};
        return {
          player_id: pid,
          display_name: hb.display_name,
          color: hb.color,
          session_id: hb.session_id,
          platform: getPlatform(hb) || 'unknown',
          start_time: hb.session_start ?? hb.timestamp,
          duration: 0,
          scenes_visited: p.scene ? [p.scene] : [],
          scene: p.scene,
          avg_fps: p.fps ?? 0,
          avg_mem: p.memory_mb ?? 0,
          live: true,
        };
      })
  ), [heartbeats]);

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
      && (session.live || minDuration <= 0 || sessionDuration(session) >= minDuration)
    ));
  }, [historicalSessions, liveSessionRows, selectedPlatforms, selectedSceneFilter, minDuration]);

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
  // Peers = other live players besides the active one. Drives the PEERS toggle's
  // enabled state (no peers → nothing to show, so the button reads disabled).
  const otherPeerCount = Math.max(0, pids.length - 1);

  useEffect(() => {
    if (pids.length > 0) setLastLivePlayerCount(pids.length);
  }, [pids.length]);

  // Birdseye/3D require a live player; fall back to Dashboard when none.
  useEffect(() => {
    if (!hasLive && liveView !== 'dashboard') setLiveView('dashboard');
  }, [hasLive, liveView]);

  const activeFilterCount =
    (selectedSceneFilter !== 'all' ? 1 : 0) +
    (KNOWN_PLATFORMS.filter((p) => p !== 'server').length - [...selectedPlatforms].filter((p) => p !== 'server').length > 0 ? 1 : 0) +
    (minDuration !== DEFAULT_HISTORY_MIN_DURATION ? 1 : 0);

  const playerCountLabel = pids.length > 0
    ? `${pids.length} ${pids.length === 1 ? 'player' : 'players'}`
    : lastLivePlayerCount > 0
      ? `${lastLivePlayerCount} last live`
      : `${filteredDashboardSessions.length} sessions`;

  const activeId = selectedPlayerId && filteredHeartbeats[selectedPlayerId] ? selectedPlayerId : pids[0];
  const activeHb = filteredHeartbeats[activeId];
  const activeLabel = activeHb?.display_name || activeId;
  const activeHistory = history[activeId];
  const focusedGeo = useMemo(() => (
    focusPlayerId ? geoPlayers.find((player) => player.player_id === focusPlayerId) : undefined
  ), [focusPlayerId, geoPlayers]);
  // player_id -> {city, country} so player lists can show location instead of
  // the raw id. Geo data only lives on geoPlayers, not on the heartbeat.
  const geoByPlayer = useMemo(() => {
    const map: Record<string, { city?: string; country?: string; country_code?: string }> = {};
    for (const g of geoPlayers) {
      if (g.player_id && !map[g.player_id]) {
        map[g.player_id] = { city: g.city, country: g.country, country_code: g.country_code };
      }
    }
    return map;
  }, [geoPlayers]);

  // History sessions enriched with geo (city/country) joined by player_id, so the
  // session list can show location. Only fills fields the row doesn't already have.
  const historySessionsWithGeo = useMemo(() => (
    filteredHistoricalSessions.map((s) => {
      const geo = s.player_id ? geoByPlayer[s.player_id] : undefined;
      if (!geo || (s.city && s.country)) return s;
      return {
        ...s,
        city: s.city || geo.city,
        country: s.country || geo.country,
        country_code: s.country_code || geo.country_code,
      };
    })
  ), [filteredHistoricalSessions, geoByPlayer]);
  const staleAge = activeHb ? (activeHb.timestamp ? (Date.now() - activeHb.timestamp * 1000) / 1000 : 0) : 0;
  const liveSceneName = selectedSceneFilter === 'all'
    ? (activeHb?.player?.scene || '')
    : selectedSceneFilter;
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

  // The 3D viewport element, reused inline and inside the fullscreen overlay.
  const viewport3D = (
    <Viewport3D
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
    />
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
            onClear={() => { setFocusPlayerId(null); setShowTagEditor(false); }}
            onTagClick={() => setShowTagEditor(!showTagEditor)}
          />
        ) : undefined
      }
      dashboardVersion={DASHBOARD_BUILD_VERSION || health?.dashboard_version}
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
            { id: 'birdseye', label: 'Birdseye', enabled: hasLive },
            { id: '3d', label: '3D', enabled: hasLive },
          ] as const).map((v) => (
            <button
              key={v.id}
              onClick={() => v.enabled && setLiveView(v.id)}
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

      <FiltersDrawer
        open={showFilters}
        onClose={() => setShowFilters(false)}
        platforms={availablePlatforms}
        selectedPlatforms={selectedPlatforms}
        onTogglePlatform={togglePlatform}
        scenes={sceneFilterOptions}
        selectedScene={selectedSceneFilter}
        onSelectScene={setSelectedSceneFilter}
        minDuration={minDuration}
        onSetMinDuration={setMinDuration}
        onReset={resetFilters}
      />

      <PlayerBottomSheet
        open={showPlayerSheet}
        onClose={() => setShowPlayerSheet(false)}
        players={Object.values(filteredHeartbeats)}
        geoByPlayer={geoByPlayer}
        activeId={activeId}
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
                <div className="flex min-h-0 flex-[1.1] flex-col border-b-2 border-black bg-bg-card/40">
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
                {/* Bottom stripe: info cards (historical summary) */}
                <div className="min-h-0 flex-1 overflow-y-auto">
                  <div className="p-4 sm:p-6 pb-0">
                  </div>
                  <HomeStats sessions={filteredDashboardSessions} serverStats={serverStats} />
                </div>
              </div>
            ) : !activeHb ? (
              <div className="flex h-full items-center justify-center p-6 text-center text-sm italic text-text-muted">
                No active player. Open Dashboard or adjust filters.
              </div>
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
                      <Info label="FPS" value={`${Math.round(activeHb?.player?.fps ?? 0)}${activeHb?.player?.focused === false ? ' (bg)' : ''}`} />
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
                <LiveMap
                  ghosts={liveGhosts}
                  sceneName={birdseyeSceneName}
                  activePlayerId={activeId}
                  onSelectGhost={(pid) => setBirdseyeDetailId(pid)}
                />

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
                      <RetroButton
                        variant="primary"
                        onClick={() => {
                          setSelectedPlayerId(birdseyeDetailId);
                          setBirdseyeDetailId(null);
                          setLiveView('3d');
                          setFollowPlayer(true);
                        }}
                        className="mt-2 w-full py-1 text-[0.625rem]"
                      >
                        Ver 3D
                      </RetroButton>
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
          <GlobeView
            players={filteredGeoPlayers}
            onSelectPlayer={(playerId) => {
              setFocusPlayerId(playerId);
              setShowTagEditor(true);
              window.history.replaceState(null, '', `?player=${encodeURIComponent(playerId)}`);
            }}
          />
        </div>
      )}

      {activeTab === 'heatmap' && (
        <div className="flex h-full flex-col gap-3 overflow-hidden p-4">
          <div className="flex border-2 border-black xl:hidden">
            <button
              type="button"
              onClick={() => setHeatmapMobileView('scenes')}
              className={`subtab-btn ${heatmapMobileView === 'scenes' ? 'subtab-btn-active' : ''}`}
            >
              Escenas
            </button>
            <button
              type="button"
              onClick={() => setHeatmapMobileView('map')}
              className={`subtab-btn ${heatmapMobileView === 'map' ? 'subtab-btn-active' : ''}`}
            >
              {heatmapTargetScene ? 'Mapa' : 'Stats'}
            </button>
          </div>

          <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
          <RetroCard title="Scenes" className={`min-h-0 overflow-hidden ${heatmapMobileView === 'map' ? 'hidden xl:block' : ''}`}>
            <SceneIndex
              sessions={filteredDashboardSessions}
              scenes={availableSceneFilters}
              selectedScene={selectedSceneFilter}
              onSelectScene={(scene) => {
                setSelectedSceneFilter(scene);
                setHeatmapMobileView('map');
              }}
            />
          </RetroCard>

          <div className={`min-h-0 relative border-4 border-black shadow-retro overflow-hidden ${heatmapMobileView === 'scenes' ? 'hidden xl:block' : ''}`}>
            {!heatmapTargetScene ? (
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

                <div className="mt-4 border-2 border-black bg-bg-card shadow-[2px_2px_0px_0px_black]">
                  <div className="border-b-2 border-black px-3 py-2 text-[0.625rem] font-black uppercase text-text-muted">
                    Top scenes
                  </div>
                  {heatmapSummary.topScenes.length === 0 ? (
                    <div className="px-3 py-4 text-center text-xs text-text-muted">No scene data yet.</div>
                  ) : (
                    heatmapSummary.topScenes.map((opt) => (
                      <button
                        key={opt.scene}
                        type="button"
                        onClick={() => {
                          setSelectedSceneFilter(opt.scene);
                          setHeatmapMobileView('map');
                        }}
                        className="flex w-full items-center justify-between gap-3 border-b border-black/40 px-3 py-2 text-left last:border-b-0 hover:bg-accent/5"
                      >
                        <span className="min-w-0 truncate text-xs font-black text-accent">{opt.scene}</span>
                        <span className="shrink-0 text-[0.625rem] font-black uppercase text-text-muted">
                          {opt.sessions} sessions · {formatPlayTime(opt.playTime)}
                        </span>
                      </button>
                    ))
                  )}
                  <div className="px-3 py-2 text-[0.5625rem] text-text-muted">
                    Pick a scene to open its heatmap.
                  </div>
                </div>
              </div>
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
              <div className="flex gap-2">
                <RetroButton
                  variant="secondary"
                  onClick={() => {
                    setSelectedSceneFilter('all');
                    setHeatmapMobileView('scenes');
                  }}
                  className="px-2 py-1 text-[0.625rem]"
                >
                  Todas las escenas
                </RetroButton>
                <RetroButton
                  variant="secondary"
                  onClick={() => setHeatmapMobileView('scenes')}
                  className="px-2 py-1 text-[0.625rem] xl:hidden"
                >
                  Cambiar escena
                </RetroButton>
              </div>
              <div className="grid grid-cols-2 gap-2 text-[0.5rem] font-bold uppercase sm:grid-cols-4">
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-green-500" /> Low</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-yellow-500" /> Med</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-orange-500" /> High</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-red-500" /> Crit</div>
              </div>
            </div>
            <Heatmap3D data={filteredHeatmapData} resolution={heatmapRes} />
            </>
            )}
          </div>
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div className="flex h-full flex-col gap-3 overflow-hidden p-4">
          {/* Mobile pane toggle: session list vs playback. */}
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
              onClick={() => setHistoryMobileView('player')}
              disabled={!selectedSession}
              className={`subtab-btn ${historyMobileView === 'player' ? 'subtab-btn-active' : ''}`}
            >
              Reproducción
            </button>
          </div>

          <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
            {/* Left: live session list sidebar */}
            <RetroCard title="Sesiones" className={`min-h-0 overflow-hidden ${historyMobileView === 'player' ? 'hidden xl:block' : ''}`}>
              <div className="h-full overflow-y-auto">
                <HistoricalTable
                  sessions={historySessionsWithGeo}
                  onSelectSession={handleSelectHistorySession}
                  selectedSessionId={selectedSession?.session_id}
                />
              </div>
            </RetroCard>

            {/* Right: playback */}
            <div className={`min-h-0 overflow-y-auto ${historyMobileView === 'list' ? 'hidden xl:block' : ''}`}>
              {!selectedSession ? (
                <div className="min-h-full p-1">
                  <HistoryOverview sessions={filteredHistoricalSessions} />
                </div>
              ) : playbackLoading ? (
                <div className="flex h-full items-center justify-center">
                  <div className="flex items-center gap-3 text-xs font-black uppercase tracking-widest text-text-muted">
                    <span className="h-4 w-4 animate-spin border-2 border-text-muted border-t-accent rounded-full" />
                    Loading session…
                  </div>
                </div>
              ) : (
                <SessionPlayback heartbeats={playbackData} session={selectedSession} />
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
          scenes={sceneFilterOptions}
          selectedScene={selectedSceneFilter}
          onSelectScene={setSelectedSceneFilter}
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
