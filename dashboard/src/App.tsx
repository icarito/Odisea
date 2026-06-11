import { useState, useEffect, useMemo, useRef } from 'react';
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
import { Viewport3D } from './components/Viewport3D';
import { Heatmap3D } from './components/Heatmap3D';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { SessionPlayback } from './components/SessionPlayback';
import { DashboardLayout } from './components/DashboardLayout';
import { PlayerBottomSheet } from './components/PlayerBottomSheet';
import { PlatformFilter } from './components/PlatformFilter';
import { RetroCard, RetroButton, RetroSelect } from './components/retro';
import { useTelemetry } from './hooks/useTelemetry';
import { useWebSocket } from './hooks/useWebSocket';
import { useLayoutPersistence } from './hooks/useLayoutPersistence';
import { getHeatmap, getHistoricalSessions, getGhostData, getScenes } from './api';
import { Maximize2, Play, X } from 'lucide-react';

type Tab = 'live' | 'heatmap' | 'history' | 'playback';

const KNOWN_PLATFORMS = ['server', 'android', 'linux', 'windows', 'macos', 'web'];

type GitCommit = {
  sha: string;
  date: string;
  message: string;
};

const normalizePlatform = (value: any): string | null => {
  if (typeof value !== 'string' || value.trim() === '') return null;
  return value.trim().toLowerCase();
};

const getPlatform = (item: any): string | null => (
  normalizePlatform(item?.platform ?? item?.player?.platform)
);

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

const sessionScenes = (session: any): string[] => {
  if (Array.isArray(session?.scenes_visited)) return session.scenes_visited.filter(Boolean);
  if (typeof session?.scenes_visited === 'string') {
    return session.scenes_visited.split(',').map((s: string) => s.trim()).filter(Boolean);
  }
  return session?.scene ? [session.scene] : [];
};

const isUsefulSceneName = (scene: any): scene is string => {
  if (typeof scene !== 'string') return false;
  const normalized = scene.trim().toLowerCase();
  return Boolean(normalized) && !['?', 'unknown', 'desconocida', 'desconocido', 'undefined', 'null'].includes(normalized);
};

const HomeStats = ({ sessions, commits }: { sessions: any[]; commits: GitCommit[] }) => {
  const cleanSessions = useMemo(() => (
    sessions.filter((session) => getPlatform(session) !== 'server')
  ), [sessions]);

  const stats = useMemo(() => {
    const fpsValues = cleanSessions.map((s) => Number(s.avg_fps)).filter((n) => Number.isFinite(n));
    const totalDuration = cleanSessions.reduce((sum, s) => sum + (Number(s.duration) || 0), 0);
    const avgFps = fpsValues.reduce((sum, fps) => sum + fps, 0) / (fpsValues.length || 1);
    const lowPct = cleanSessions.length
      ? cleanSessions.filter((s) => (Number(s.avg_fps) || 0) < 30).length * 100 / cleanSessions.length
      : 0;
    const lastSession = cleanSessions.reduce((latest, s) => {
      const ts = Number(s.start_time) || 0;
      return ts > latest ? ts : latest;
    }, 0);
    return { avgFps, totalDuration, lowPct, lastSession };
  }, [cleanSessions]);

  const fpsSeries = useMemo(() => (
    [...cleanSessions]
      .filter((s) => Number(s.start_time) > 0)
      .sort((a, b) => Number(a.start_time) - Number(b.start_time))
      .map((s) => ({
        timestamp: Number(s.start_time),
        date: new Date(Number(s.start_time) * 1000).toISOString().slice(0, 10),
        label: formatDateTime(Number(s.start_time)),
        avg_fps: Number(s.avg_fps) || 0,
      }))
  ), [cleanSessions]);

  const sessionsByDay = useMemo(() => {
    const grouped = new Map<string, number>();
    cleanSessions.forEach((s) => {
      const ts = Number(s.start_time) || 0;
      if (!ts) return;
      const day = new Date(ts * 1000).toISOString().slice(0, 10);
      grouped.set(day, (grouped.get(day) || 0) + 1);
    });
    return Array.from(grouped.entries())
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, count]) => ({ date, count }));
  }, [cleanSessions]);

  const commitLines = useMemo(() => {
    if (fpsSeries.length === 0) return [];
    const minTs = fpsSeries[0].timestamp;
    const maxTs = fpsSeries[fpsSeries.length - 1].timestamp;
    return commits
      .map((commit) => ({
        ...commit,
        timestamp: Math.floor(new Date(commit.date).getTime() / 1000),
      }))
      .filter((commit) => commit.timestamp >= minTs && commit.timestamp <= maxTs);
  }, [commits, fpsSeries]);

  const statCards: Array<Array<{ label: string; value: string; color?: string }>> = [
    [
      { label: 'Total Sessions', value: cleanSessions.length.toString() },
      { label: 'Total Play Time', value: formatPlayTime(stats.totalDuration) },
    ],
    [
      { label: 'Avg FPS Global', value: stats.avgFps.toFixed(1), color: fpsColor(stats.avgFps) },
      { label: '% Low FPS', value: `${stats.lowPct.toFixed(1)}%`, color: fpsColor(100 - stats.lowPct) },
    ],
    [
      { label: 'Last Session', value: formatDateTime(stats.lastSession) },
      { label: 'Scenes', value: new Set(cleanSessions.flatMap(sessionScenes)).size.toString() },
    ],
  ];

  const commitTooltip = ({ active, payload }: any) => {
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
        <text
          x={x + 4}
          y={y + 12}
          fill="#d29922"
          fontSize={9}
          transform={`rotate(90 ${x + 4} ${y + 12})`}
        >
          {shortSha}
        </text>
      </g>
    );
  };

  return (
    <div className="flex flex-col gap-4 p-4 sm:p-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {statCards.map((row) => (
          <RetroCard key={row.map((card) => card.label).join('-')}>
            <div className="grid grid-cols-2 gap-4">
              {row.map((card) => (
                <div key={card.label} className="min-w-0">
                  <div className="truncate text-xl font-black tracking-tighter sm:text-2xl" style={card.color ? { color: card.color } : undefined}>
                    {card.value}
                  </div>
                  <div className="mt-1 text-[0.625rem] font-black uppercase text-text-muted">{card.label}</div>
                </div>
              ))}
            </div>
          </RetroCard>
        ))}
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-5">
        <RetroCard title="FPS Over Time" className="xl:col-span-3">
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
              <LineChart data={fpsSeries}>
                <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
                <XAxis dataKey="timestamp" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} tickFormatter={(v) => new Date(Number(v) * 1000).toISOString().slice(5, 10)} />
                <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
                <Tooltip content={commitTooltip} />
                {commitLines.map((commit) => (
                  <ReferenceLine
                    key={commit.sha}
                    x={commit.timestamp}
                    stroke="#d29922"
                    strokeDasharray="3 3"
                    label={renderCommitLabel(commit)}
                  />
                ))}
                <Line type="monotone" dataKey="avg_fps" stroke="#7fd1ff" dot={{ r: 3 }} strokeWidth={2} isAnimationActive={false} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </RetroCard>

        <RetroCard title="Sessions Per Day" className="xl:col-span-2">
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
              <BarChart data={sessionsByDay}>
                <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
                <XAxis dataKey="date" stroke="#666" fontSize={10} tickFormatter={(v) => String(v).slice(5)} />
                <YAxis stroke="#666" fontSize={10} allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="count" fill="#7fd1ff" isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </RetroCard>
      </div>
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
    return scenes.map((scene) => {
      const sceneSessions = sessions
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
          avg_fps: Number(session.avg_fps) || 0,
        })),
      };
    }).filter((stat) => stat.sessions > 0 || scenes.includes(stat.scene));
  }, [sessions, scenes]);

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
  const { heartbeats, isConnected, alerts, history } = useTelemetry();
  const { lastMessage } = useWebSocket();
  const { layout, updateLayout } = useLayoutPersistence();
  
  const activeTab = layout.activeTab as Tab;
  const setActiveTab = (t: Tab) => updateLayout({ activeTab: t });

  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);

  // Live tab view toggle: 2D birdseye map vs 3D perspective.
  const [liveView, setLiveView] = useState<'birdseye' | '3d'>('3d');
  // CSS overlay fullscreen for the 3D canvas (NOT the browser Fullscreen API,
  // which is unreliable on mobile).
  const [fs3d, setFs3d] = useState(false);
  // Player list bottom sheet (opened from the header counter).
  const [showPlayerSheet, setShowPlayerSheet] = useState(false);

  // Heatmap State
  const [heatmapRes, setHeatmapRes] = useState(5);
  const [heatmapMobileView, setHeatmapMobileView] = useState<'scenes' | 'map'>('scenes');

  // Available scenes (fetched from backend, not hardcoded)
  const [scenes, setScenes] = useState<string[]>([]);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState<any[]>([]);
  const [selectedSession, setSelectedSession] = useState<any>(null);
  const [playbackData, setPlaybackData] = useState<any[]>([]);
  const [commits, setCommits] = useState<GitCommit[]>([]);
  const [selectedPlatforms, setSelectedPlatforms] = useState<Set<string>>(
    () => new Set(KNOWN_PLATFORMS.filter((platform) => platform !== 'server'))
  );
  const [selectedSceneFilter, setSelectedSceneFilter] = useState('all');
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
      const key = `${playerId}|${alertType}`;
      const now = Date.now();
      const lastToast = alertToastTimes.current.get(key) || 0;
      if (now - lastToast < 60000) return;
      alertToastTimes.current.set(key, now);
      toast(lastMessage.message, { icon: '🔥', duration: 4000 });
    }
  }, [lastMessage]);

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
        session_id: hb.session_id,
        scene: p.scene,
        platform: getPlatform(hb),
        pos_x: pos[0],
        pos_y: pos[1],
        pos_z: pos[2],
        fps: p.fps,
        last_seen: hb.timestamp
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

  useEffect(() => {
    getHistoricalSessions()
      .then((d) => setHistoricalSessions(Array.isArray(d) ? d : []))
      .catch(() => setHistoricalSessions([]));

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
    setActiveTab('playback');
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
    }
  };

  const [followPlayer, setFollowPlayer] = useState(true);
  const [wireframe, setWireframe] = useState(false);
  const [manualScene, setManualScene] = useState<string | null>(null);

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
    ? (availableSceneFilters[0] || 'Dome_Crio')
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

  const filteredHistoricalSessions = useMemo(() => (
    historicalSessions.filter((session) => platformAllowed(session) && sceneAllowed(session))
  ), [historicalSessions, selectedPlatforms, selectedSceneFilter]);

  const filteredHeatmapData = useMemo(() => (
    (heatmapData ?? []).filter((item) => platformAllowed(item) && sceneAllowed(item))
  ), [heatmapData, selectedPlatforms, selectedSceneFilter]);

  useEffect(() => {
    if (activeTab === 'heatmap') {
      getHeatmap(heatmapTargetScene, heatmapRes)
        .then((d) => setHeatmapData(Array.isArray(d) ? d : []))
        .catch(() => setHeatmapData([]));
    }
  }, [activeTab, heatmapTargetScene, heatmapRes]);

  const togglePlatform = (platform: string) => {
    setSelectedPlatforms((prev) => {
      const next = new Set(prev);
      if (next.has(platform)) next.delete(platform);
      else next.add(platform);
      return next;
    });
  };

  const pids = Object.keys(filteredHeartbeats);

  useEffect(() => {
    if (showHeatmap && manualScene) {
      getHeatmap(manualScene).then(setHeatmapData).catch(console.error);
    } else if (showHeatmap && selectedSceneFilter !== 'all') {
      getHeatmap(selectedSceneFilter).then(setHeatmapData).catch(console.error);
    } else {
      setHeatmapData(undefined);
    }
  }, [showHeatmap, manualScene, selectedSceneFilter]);

  const activeId = selectedPlayerId && filteredHeartbeats[selectedPlayerId] ? selectedPlayerId : pids[0];
  const activeHb = filteredHeartbeats[activeId];
  const activeHistory = history[activeId];
  const staleAge = activeHb ? (activeHb.timestamp ? (Date.now() - activeHb.timestamp * 1000) / 1000 : 0) : 0;

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
      wireframe={wireframe}
      sceneName={manualScene || activeHb?.player.scene || ""}
      staleAge={staleAge}
      heatmapData={showHeatmap ? heatmapData : undefined}
      liveGhosts={liveGhostMarkers}
      hud={activeHb ? { fps: activeHb.player?.fps, scene: activeHb.player?.scene } : null}
    />
  );

  return (
    <DashboardLayout
      onLogout={onLogout}
      isConnected={isConnected}
      activeTab={activeTab}
      setActiveTab={setActiveTab}
      playerCount={pids.length}
      onPlayersClick={() => setShowPlayerSheet(true)}
      isSessionSelected={!!selectedSession}
      headerControls={
        <div className="flex max-w-[52vw] items-center gap-2 sm:max-w-none">
          <div className="w-32 shrink-0">
            <RetroSelect
              value={selectedSceneFilter}
              onChange={(event) => setSelectedSceneFilter(event.target.value)}
              className="py-1 px-2 text-[0.625rem]"
              title="Filter scene"
            >
              <option value="all">All scenes</option>
              {availableSceneFilters.map((scene) => <option key={scene} value={scene}>{scene}</option>)}
            </RetroSelect>
          </div>
          <PlatformFilter
            platforms={availablePlatforms}
            selected={selectedPlatforms}
            onToggle={togglePlatform}
          />
        </div>
      }
    >
      <Toaster position="bottom-right" />

      <PlayerBottomSheet
        open={showPlayerSheet}
        onClose={() => setShowPlayerSheet(false)}
        players={Object.values(filteredHeartbeats)}
        activeId={activeId}
        onSelect={(pid) => setSelectedPlayerId(pid)}
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
          <div className="flex-1 min-h-0">{viewport3D}</div>
        </div>
      )}
      
      {activeTab === 'live' && (
        pids.length === 0 ? (
          <HomeStats sessions={filteredHistoricalSessions} commits={commits} />
        ) : (
        <div className="flex flex-col h-full min-h-0">
          {/* Toolbar: view toggle (Birdseye / 3D) + view-specific controls */}
          <div className="shrink-0 flex flex-wrap items-center gap-2 p-2 border-b-2 border-black bg-bg-card/60">
            <div className="flex border-2 border-black">
              <button
                onClick={() => setLiveView('birdseye')}
                className={`px-3 py-1 text-[0.625rem] font-black uppercase ${liveView === 'birdseye' ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted'}`}
              >
                Birdseye
              </button>
              <button
                onClick={() => setLiveView('3d')}
                className={`px-3 py-1 text-[0.625rem] font-black uppercase border-l-2 border-black ${liveView === '3d' ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted'}`}
              >
                3D
              </button>
            </div>

            <RetroSelect
              value={manualScene || (selectedSceneFilter === 'all' ? activeHb?.player.scene : selectedSceneFilter) || ""}
              onChange={(e) => setManualScene(e.target.value)}
              className="py-1 px-2 text-[0.625rem] w-32"
            >
              <option value="">AUTO SCENE</option>
              {scenes.map(s => <option key={s} value={s}>{s}</option>)}
            </RetroSelect>

            {liveView === '3d' && (
              <div className="flex gap-1 flex-wrap">
                <RetroButton variant={followPlayer ? 'primary' : 'secondary'} onClick={() => setFollowPlayer(!followPlayer)} className="py-1 px-2 text-[0.625rem]">FOLLOW</RetroButton>
                <RetroButton variant={wireframe ? 'primary' : 'secondary'} onClick={() => setWireframe(!wireframe)} className="py-1 px-2 text-[0.625rem]">MESH</RetroButton>
                <RetroButton variant={showHeatmap ? 'primary' : 'secondary'} onClick={() => setShowHeatmap(!showHeatmap)} className="py-1 px-2 text-[0.625rem]">HEAT</RetroButton>
                <RetroButton variant={showLiveGhosts ? 'primary' : 'secondary'} onClick={() => setShowLiveGhosts(!showLiveGhosts)} className="py-1 px-2 text-[0.625rem]">PEERS</RetroButton>
                <RetroButton variant="secondary" onClick={() => setFs3d(true)} className="py-1 px-2" title="Fullscreen 3D"><Maximize2 size={14} /></RetroButton>
              </div>
            )}
          </div>

          {/* View area fills all remaining space (no fixed heights). */}
          <div className="flex-1 min-h-0 relative">
            {!activeHb ? (
              <div className="h-full flex items-center justify-center p-6 text-center text-text-muted italic text-sm">
                No active player. Tap the player counter above to pick one.
              </div>
            ) : liveView === '3d' ? (
              <div className="absolute inset-0">{viewport3D}</div>
            ) : (
              <LiveMap ghosts={liveGhosts} sceneName={manualScene || activeHb?.player.scene || ""} />
            )}
          </div>
        </div>
        )
      )}

      {activeTab === 'heatmap' && (
        <div className="flex h-full flex-col gap-3 overflow-hidden p-4">
          <div className="flex border-2 border-black xl:hidden">
            <button
              type="button"
              onClick={() => setHeatmapMobileView('scenes')}
              className={`flex-1 px-3 py-2 text-[0.625rem] font-black uppercase ${heatmapMobileView === 'scenes' ? 'bg-accent text-black' : 'bg-bg-card text-text-muted'}`}
            >
              Escenas
            </button>
            <button
              type="button"
              onClick={() => setHeatmapMobileView('map')}
              className={`flex-1 border-l-2 border-black px-3 py-2 text-[0.625rem] font-black uppercase ${heatmapMobileView === 'map' ? 'bg-accent text-black' : 'bg-bg-card text-text-muted'}`}
            >
              Mapa
            </button>
          </div>

          <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
          <RetroCard title="Scenes" className={`min-h-0 overflow-hidden ${heatmapMobileView === 'map' ? 'hidden xl:block' : ''}`}>
            <SceneIndex
              sessions={filteredHistoricalSessions}
              scenes={availableSceneFilters}
              selectedScene={heatmapTargetScene}
              onSelectScene={(scene) => {
                setSelectedSceneFilter(scene);
                setHeatmapMobileView('map');
              }}
            />
          </RetroCard>

          <div className={`min-h-0 relative border-4 border-black shadow-retro overflow-hidden ${heatmapMobileView === 'scenes' ? 'hidden xl:block' : ''}`}>
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
                  onClick={() => setSelectedSceneFilter('all')}
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
              <div className="hidden grid-cols-2 gap-2 text-[0.5rem] font-bold uppercase sm:grid lg:grid-cols-4">
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-green-500" /> Low</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-yellow-500" /> Med</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-orange-500" /> High</div>
                <div className="flex items-center gap-1"><div className="h-2 w-2 bg-red-500" /> Crit</div>
              </div>
            </div>
            <Heatmap3D data={filteredHeatmapData} resolution={heatmapRes} />
          </div>
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div className="flex-1 p-4 sm:p-6 overflow-y-auto">
          <RetroCard title="HISTORICAL ARCHIVE">
             <HistoricalTable sessions={filteredHistoricalSessions} onSelectSession={handleSelectHistorySession} />
          </RetroCard>
        </div>
      )}

      {activeTab === 'playback' && (
        <div className="flex-1 p-4 sm:p-6 overflow-y-auto flex flex-col gap-6">
          <div className="flex justify-between items-center bg-bg-card border-4 border-black p-4 shadow-retro">
            <div>
              <h2 className="text-sm font-black text-accent uppercase tracking-tighter flex items-center gap-2">
                <Play size={16} /> PLAYBACK MODULE
              </h2>
              <div className="text-[0.625rem] text-text-muted font-mono mt-1 opacity-50">{selectedSession?.session_id}</div>
            </div>
            <RetroButton
              variant="secondary"
              onClick={() => setActiveTab('history')}
              className="py-1 px-4 text-xs"
            >
              EXIT
            </RetroButton>
          </div>
          <SessionPlayback heartbeats={playbackData} session={selectedSession} />
        </div>
      )}
    </DashboardLayout>
  );
}

function App() {
  const [token, setToken] = useState<string | null>(sessionStorage.getItem("odisea_token"));

  if (!token) {
    return <LoginScreen onLogin={(t) => {
      sessionStorage.setItem("odisea_token", t);
      setToken(t);
    }} />;
  }

  return <Dashboard onLogout={() => {
    sessionStorage.removeItem("odisea_token");
    setToken(null);
  }} />;
}

export default App;
