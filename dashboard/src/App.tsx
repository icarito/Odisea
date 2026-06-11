import { useState, useEffect } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { LoginScreen } from './components/LoginScreen';
import { PlayerCard } from './components/PlayerCard';
import { Viewport3D } from './components/Viewport3D';
import { FpsTimeline } from './components/FpsTimeline';
import { MemTimeline } from './components/MemTimeline';
import { Heatmap3D } from './components/Heatmap3D';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { SessionPlayback } from './components/SessionPlayback';
import { useTelemetry } from './hooks/useTelemetry';
import { useWebSocket } from './hooks/useWebSocket';
import { getHeatmap, getHistoricalSessions, getGhostData, getScenes } from './api';

type Tab = 'live' | 'heatmap' | 'history' | 'playback';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, peersConnected, isConnected, alerts, history } = useTelemetry();
  const { lastMessage } = useWebSocket();
  const [activeTab, setActiveTab] = useState<Tab>('live');
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);

  // Heatmap State
  const [heatmapScene, setHeatmapScene] = useState('Dome_Crio');
  const [heatmapRes, setHeatmapRes] = useState(5);

  // Available scenes (fetched from backend, not hardcoded)
  const [scenes, setScenes] = useState<string[]>([]);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState<any[]>([]);
  const [selectedSession, setSelectedSession] = useState<any>(null);
  const [playbackData, setPlaybackData] = useState<any[]>([]);

  // Live State
  const [liveGhosts, setLiveGhosts] = useState<any[]>([]);

  useEffect(() => {
    if (alerts.length > 0) {
        const latest = alerts[0];
        toast(latest.message, {
            icon: latest.type === 'disconnect' ? '❌' : '⚠️',
            style: {
                borderRadius: '4px',
                background: '#13161c',
                color: '#d7dbe0',
                border: '1px solid #232833',
                fontSize: '12px',
                fontFamily: 'monospace'
            },
        });
    }
  }, [alerts]);

  useEffect(() => {
    if (lastMessage?.type === 'alert') {
      toast(lastMessage.message, { icon: '🔥', duration: 4000 });
    }
  }, [lastMessage]);

  // Sync live ghosts from telemetry
  useEffect(() => {
    const active = Object.entries(heartbeats).map(([pid, hb]: [string, any]) => {
      const p = hb.player || {};
      const pos = p.position || [0,0,0];
      return {
        player_id: pid,
        session_id: hb.session_id,
        scene: p.scene,
        pos_x: pos[0],
        pos_y: pos[1],
        pos_z: pos[2],
        fps: p.fps,
        last_seen: hb.timestamp
      };
    });
    setLiveGhosts(active);
  }, [heartbeats]);

  // Fetch Heatmap
  useEffect(() => {
    if (activeTab === 'heatmap') {
      getHeatmap(heatmapScene, heatmapRes)
        .then((d) => setHeatmapData(Array.isArray(d) ? d : []))
        .catch(() => setHeatmapData([]));
    }
  }, [activeTab, heatmapScene, heatmapRes]);

  // Fetch History
  useEffect(() => {
    if (activeTab === 'history') {
      getHistoricalSessions()
        .then((d) => setHistoricalSessions(Array.isArray(d) ? d : []))
        .catch(() => setHistoricalSessions([]));
    }
  }, [activeTab]);

  // Fetch available scenes once
  useEffect(() => {
    getScenes()
      .then((d) => setScenes(Array.isArray(d) ? d : []))
      .catch(() => setScenes([]));
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
      pos_y: hb.pos_y ?? pos?.[1] ?? 0,
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

  const pids = Object.keys(heartbeats);

  useEffect(() => {
    if (showHeatmap && manualScene) {
      getHeatmap(manualScene).then(setHeatmapData).catch(console.error);
    } else {
      setHeatmapData(undefined);
    }
  }, [showHeatmap, manualScene]);
  const activeId = selectedPlayerId || pids[0];
  const activeHb = heartbeats[activeId];
  const activeHistory = history[activeId];
  const staleAge = activeHb ? (activeHb.timestamp ? (Date.now() - activeHb.timestamp * 1000) / 1000 : 0) : 0;

  const safePos = (p: any): [number, number, number] => {
    if (Array.isArray(p) && p.length >= 3) {
      return [Number(p[0]), Number(p[1]), Number(p[2])];
    }
    return [0, 0, 0];
  };

  return (
    <div className="min-h-screen bg-bg-primary text-text-primary font-mono flex flex-col">
      <Toaster position="bottom-right" />
      <header className="flex items-center gap-4 px-4 py-2 bg-bg-card border-b border-border-custom sticky top-0 z-20">
        <h1 className="text-accent font-bold text-base">ODISEA CENTRAL</h1>

        <nav className="flex gap-2 ml-6">
          {(['live', 'heatmap', 'history'] as Tab[]).map(t => (
            <button
              key={t}
              onClick={() => setActiveTab(t)}
              className={`px-3 py-1 text-[10px] uppercase font-bold rounded transition-colors ${activeTab === t ? 'bg-accent text-black' : 'text-text-muted hover:text-white hover:bg-[#1c2230]'}`}
            >
              {t}
            </button>
          ))}
          {activeTab === 'playback' && (
             <button className="px-3 py-1 text-[10px] uppercase font-bold rounded bg-accent text-black">
               Playback
             </button>
          )}
        </nav>

        <div className="flex-1" />
        <div className="flex items-center gap-4 text-xs">
          <span className="flex items-center gap-1.5">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success' : 'bg-danger'}`} />
            {isConnected ? 'online' : 'offline'}
          </span>
          <span className="text-text-muted">peers <b className="text-text-primary">{peersConnected}</b></span>
        </div>
        <button
          onClick={onLogout}
          className="px-3 py-1 bg-bg-primary border border-border-custom rounded text-xs hover:bg-[#1c2230]"
        >
          salir
        </button>
      </header>

      <main className="flex-1 flex overflow-hidden">
        {activeTab === 'live' && (
          <>
            <div className="hidden lg:flex lg:w-64 lg:shrink-0 flex-col bg-bg-primary border-r border-border-custom">
              <div className="p-2 text-[10px] uppercase text-text-muted font-bold border-b border-border-custom select-none">
                Players online ({pids.length})
              </div>
              <div className="flex-1 overflow-y-auto p-2 flex flex-col gap-2">
                {pids.length === 0 && <div className="text-center text-text-muted py-10 text-sm">Sin players</div>}
                {pids.map(pid => (
                  <PlayerCard
                    key={pid}
                    hb={heartbeats[pid]}
                    isActive={activeId === pid}
                    onClick={() => setSelectedPlayerId(pid)}
                    staleAge={(Date.now() - heartbeats[pid].timestamp * 1000) / 1000}
                  />
                ))}
              </div>
            </div>

            <div className="flex-1 flex flex-col overflow-hidden min-w-0">
              <div className="flex-1 p-4 flex flex-col gap-4 overflow-y-auto">
                <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 h-[500px] shrink-0">
                  <div className="relative">
                    <Viewport3D
                      position={activeHb ? safePos(activeHb.player.position) : [0,0,0]}
                      yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
                      pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
                      roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
                      trail={activeHistory?.trail || []}
                      follow={followPlayer}
                      wireframe={wireframe}
                      sceneName={manualScene || activeHb?.player.scene || ""}
                      staleAge={staleAge}
                      heatmapData={showHeatmap ? heatmapData : undefined}
                      liveGhosts={showLiveGhosts ? Object.values(heartbeats).filter(h => h.player_id !== activeId) : []}
                    />

                    {/* Viewport Overlays */}
                    {activeHb?.player && (
                      <div className="absolute top-6 right-6 flex flex-col gap-2 bg-bg-card/90 p-3 rounded border border-border-custom text-[10px] pointer-events-none">
                        <div className="flex justify-between gap-4">
                          <span className="text-text-muted">POS</span>
                          <span>{safePos(activeHb.player.position).map(n => n.toFixed(2)).join(", ")}</span>
                        </div>
                        <div className="flex justify-between gap-4">
                          <span className="text-text-muted">ROT</span>
                          <span>Y:{(Number(activeHb.player.yaw) || 0).toFixed(2)} P:{(Number(activeHb.player.pitch) || 0).toFixed(2)}</span>
                        </div>
                      </div>
                    )}

                    <div className="absolute bottom-6 left-6 flex items-center gap-2 pointer-events-auto flex-wrap">
                      <select
                        value={manualScene || activeHb?.player.scene || ""}
                        onChange={(e) => setManualScene(e.target.value)}
                        className="bg-bg-card/80 border border-border-custom text-[10px] px-2 py-1.5 rounded outline-none"
                      >
                        <option value="">Auto Scene</option>
                        {scenes.map(s => <option key={s} value={s}>{s}</option>)}
                      </select>
                      <button
                        onClick={() => setFollowPlayer(!followPlayer)}
                        className={`px-3 py-1.5 rounded text-xs border ${followPlayer ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                      >
                        Seguir Player
                      </button>
                      <button
                        onClick={() => setWireframe(!wireframe)}
                        className={`px-3 py-1.5 rounded text-xs border ${wireframe ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                      >
                        Wireframe
                      </button>
                      <button
                        onClick={() => setShowHeatmap(!showHeatmap)}
                        className={`px-3 py-1.5 rounded text-xs border ${showHeatmap ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                      >
                        Heatmap
                      </button>
                      <button
                        onClick={() => setShowLiveGhosts(!showLiveGhosts)}
                        className={`px-3 py-1.5 rounded text-xs border ${showLiveGhosts ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                      >
                        Live Ghosts
                      </button>
                    </div>
                  </div>
                  <div className="relative">
                     <LiveMap ghosts={liveGhosts} sceneName={manualScene || activeHb?.player.scene || ""} />
                  </div>
                </div>

                <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 h-64 shrink-0">
                  <div className="bg-bg-card p-4 rounded border border-border-custom flex flex-col min-w-0">
                    <span className="text-[10px] uppercase text-text-muted font-bold mb-2">FPS Timeline</span>
                    <FpsTimeline data={activeHistory?.fps || []} />
                  </div>
                  <div className="bg-bg-card p-4 rounded border border-border-custom flex flex-col min-w-0">
                    <span className="text-[10px] uppercase text-text-muted font-bold mb-2">Memoria (MB)</span>
                    <MemTimeline data={activeHistory?.memory || []} />
                  </div>
                </div>
              </div>
            </div>
          </>
        )}

        {activeTab === 'heatmap' && (
          <div className="flex-1 flex flex-col p-4 gap-4 overflow-hidden">
            <div className="flex gap-4 items-center bg-bg-card p-3 rounded border border-border-custom">
              <div className="flex flex-col gap-1">
                <label className="text-[10px] text-text-muted uppercase font-bold">Scene</label>
                <select
                  value={heatmapScene}
                  onChange={(e) => setHeatmapScene(e.target.value)}
                  className="bg-bg-primary border border-border-custom rounded px-2 py-1 text-xs outline-none"
                >
                  {scenes.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] text-text-muted uppercase font-bold">Resolution (m)</label>
                <input
                  type="number"
                  value={heatmapRes}
                  onChange={(e) => setHeatmapRes(Number(e.target.value))}
                  className="bg-bg-primary border border-border-custom rounded px-2 py-1 text-xs outline-none w-20"
                />
              </div>
              <div className="flex-1" />
              <div className="grid grid-cols-4 gap-4 text-[10px] uppercase font-bold">
                <div className="flex items-center gap-2"><div className="w-3 h-3 bg-green-500 rounded" /> &lt; 10% Low</div>
                <div className="flex items-center gap-2"><div className="w-3 h-3 bg-yellow-500 rounded" /> 10-30% Low</div>
                <div className="flex items-center gap-2"><div className="w-3 h-3 bg-orange-500 rounded" /> 30-50% Low</div>
                <div className="flex items-center gap-2"><div className="w-3 h-3 bg-red-500 rounded" /> &gt; 50% Low</div>
              </div>
            </div>
            <div className="flex-1">
              <Heatmap3D data={heatmapData ?? []} resolution={heatmapRes} />
            </div>
          </div>
        )}

        {activeTab === 'history' && (
          <div className="flex-1 p-6 overflow-y-auto">
            <h2 className="text-xl font-bold text-accent mb-6">HISTORICAL SESSIONS</h2>
            <HistoricalTable sessions={historicalSessions} onSelectSession={handleSelectHistorySession} />
          </div>
        )}

        {activeTab === 'playback' && (
          <div className="flex-1 p-6 overflow-y-auto flex flex-col gap-6">
            <div className="flex justify-between items-center">
              <div>
                <h2 className="text-xl font-bold text-accent">SESSION PLAYBACK</h2>
                <div className="text-xs text-text-muted font-mono">{selectedSession?.session_id}</div>
              </div>
              <button
                onClick={() => setActiveTab('history')}
                className="bg-bg-card border border-border-custom px-4 py-2 rounded text-xs hover:bg-[#1c2230]"
              >
                BACK TO LIST
              </button>
            </div>
            <SessionPlayback heartbeats={playbackData} session={selectedSession} />
          </div>
        )}
      </main>
    </div>
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
