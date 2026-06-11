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
import { getHeatmap, getHistoricalSessions, getGhostData } from './api';

type Tab = 'live' | 'heatmap' | 'history' | 'playback';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, peersConnected, isConnected, alerts, history } = useTelemetry();
  const { lastMessage } = useWebSocket();
  const [activeTab, setActiveTab] = useState<Tab>('live');
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);

  // Heatmap State
  const [heatmapData, setHeatmapData] = useState([]);
  const [heatmapScene, setHeatmapScene] = useState('Dome_Crio');
  const [heatmapRes, setHeatmapRes] = useState(5);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState([]);
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
      getHeatmap(heatmapScene, heatmapRes).then(setHeatmapData);
    }
  }, [activeTab, heatmapScene, heatmapRes]);

  // Fetch History
  useEffect(() => {
    if (activeTab === 'history') {
      getHistoricalSessions().then(setHistoricalSessions);
    }
  }, [activeTab]);

  const handleSelectHistorySession = async (session: any) => {
    setSelectedSession(session);
    setActiveTab('playback');
    try {
      const data = await getGhostData(session.player_id, session.session_id);
      if (Array.isArray(data)) {
        setPlaybackData(data.map((hb: any) => ({
          timestamp: hb.timestamp,
          fps: hb.player?.fps || 0,
          memory_mb: hb.player?.memory_mb || 0,
          pos_x: hb.player?.position?.[0] || 0,
          pos_z: hb.player?.position?.[2] || 0
        })));
      } else if (typeof data === 'string') {
          const lines = data.split('\n').filter(l => l.trim());
          const parsed = lines.map(l => {
              const hb = JSON.parse(l);
              return {
                timestamp: hb.timestamp,
                fps: hb.player?.fps || 0,
                memory_mb: hb.player?.memory_mb || 0,
                pos_x: hb.player?.position?.[0] || 0,
                pos_z: hb.player?.position?.[2] || 0
              };
          });
          setPlaybackData(parsed);
      }
    } catch (e) {
      toast.error("Failed to load session data");
    }
  };

  const [followPlayer] = useState(true);
  const [wireframe] = useState(false);
  const [manualScene] = useState<string | null>(null);

  const pids = Object.keys(heartbeats);
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
                    />
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
                  <option value="Dome_Crio">Dome_Crio</option>
                  <option value="Exterior">Exterior</option>
                  <option value="ZeroG">ZeroG</option>
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
              <Heatmap3D data={heatmapData} resolution={heatmapRes} />
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
            <SessionPlayback heartbeats={playbackData} />
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
